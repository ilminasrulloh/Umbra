//
//  MapViewModel.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 01/07/26.
//

import SwiftUI
import Combine
import MapKit
import WeatherKit
import Observation

struct NavigationDestination: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
}

extension MKLocalSearchCompletion {
    var stableID: String { "\(title)|\(subtitle)" }
}

/// Mengatur lalu lintas pencarian MapKit agar tidak overload,
/// sekaligus menjamin tombol See Routes (Foreground) selalu responsif tanpa antre.
actor SearchGate {
    private var activeLookups = 0
    private let maxConcurrent = 3
    private var backgroundWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var backgroundQueue: [UUID] = []

    /// JALUR VIP: Untuk aksi pencarian eksplisit dari user (seperti klik tombol See Routes).
    /// Langsung dieksekusi tanpa antre agar aplikasi selalu terasa responsif.
    func executeForeground<T>(_ operation: () async -> T) async -> T {
        activeLookups += 1
        defer {
            activeLookups -= 1
            processNext()
        }
        return await operation()
    }

    /// JALUR BIASA: Untuk request otomatis di background (jarak saat mengetik).
    /// Dibatasi maksimal `maxConcurrent` dan otomatis dibuang jika Task dibatalkan oleh ketikan baru.
    func executeBackground<T>(_ operation: () async -> T) async -> T? {
        if Task.isCancelled { return nil }
        
        if activeLookups < maxConcurrent {
            activeLookups += 1
            defer {
                activeLookups -= 1
                processNext()
            }
            return await operation()
        }
        
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                backgroundWaiters[id] = continuation
                backgroundQueue.append(id)
            }
            
            if Task.isCancelled {
                processNext()
                return nil
            }
            
            defer {
                activeLookups -= 1
                processNext()
            }
            return await operation()
        } onCancel: {
            Task { await cancelBackgroundWaiter(id: id) }
        }
    }

    private func cancelBackgroundWaiter(id: UUID) {
        if let continuation = backgroundWaiters.removeValue(forKey: id) {
            backgroundQueue.removeAll { $0 == id }
            continuation.resume()
        }
    }

    private func processNext() {
        while !backgroundQueue.isEmpty {
            let id = backgroundQueue.removeFirst()
            if let continuation = backgroundWaiters.removeValue(forKey: id) {
                activeLookups += 1
                continuation.resume()
                return
            }
        }
    }
}

@Observable
class MapViewModel: NSObject, MKLocalSearchCompleterDelegate {
    var locationManager = LocationManager()
    
    var results: [MKLocalSearchCompletion] = []
    var temperature: String = "27°"
    var uvIndex: Int = 4
    var weatherSymbolName: String = "cloud.sun"
    var feelsLike: String = "Feels like 32°"
    var uvCategory: String = "Moderate UV Index"
    
    let weatherService = WeatherService.shared
    private let completer = MKLocalSearchCompleter()
    
    var pingWeatherManager = false
    var userCurrentPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    var userOriginText = ""
    var userDestinationText = ""
    var showDestination = true
    
    var calculatedRoutes: [MKRoute] = []
    var shadedRoute: RouteResult?
    
    var routeOptions: [RouteOption] {
        var options: [RouteOption] = []
        
        if let shaded = shadedRoute, !shaded.coordinates.isEmpty {
            options.append(RouteOption(
                kind: "shaded",
                shadePercent: shaded.shadePercent,
                subtitle: shaded.shadePercent >= 40 ? "Recommended - stays mostly shaded" : "Some sunshine along the way",
                minutes: max(Int(shaded.estimatedTime/60), 1),
                meters: Int(shaded.totalLength),
                isRecommended: true))
        }
        
        if let plain = calculatedRoutes.first {
            options.append(RouteOption(
                kind: "fastest",
                shadePercent: 0,
                subtitle: "Fastest",
                minutes: max(Int(plain.expectedTravelTime/60), 1),
                meters: Int(plain.distance),
                isRecommended: false))
        }
        
        return options
    }
    
    private var routeGraph: RouteGraph?
    private var routePlanner: RoutePlanner?
    private let snapThresholdMeters: CLLocationDistance = 20
    
    private var searchDebounceTask: Task<Void, Never>?
    private var distanceCache: [String: String] = [:]
    private var distanceResolutionTask: Task<Void, Never>?

    // Menggunakan SearchGate baru dengan pembagian prioritas
    private let searchGate = SearchGate()
    
    override init() {
        super.init()
        InitSearchCompleter()
        loadRouteGraph()
    }
    
    func InitSearchCompleter() {
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }
    
    func SearchLocation(query: String) {
        searchDebounceTask?.cancel()
        
        // Membersihkan memory cache setiap ada input baru agar tidak overflow
        distanceCache.removeAll()
        
        guard !query.isEmpty else {
            results = []
            return
        }
        
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms debounce
            guard !Task.isCancelled else { return }
            completer.queryFragment = query
        }
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
//        loadDistances(for: results)
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
    
    /// Menyelesaikan koordinat tujuan menggunakan JALUR VIP (Foreground)
    @MainActor
    func resolveDestination(for completion: MKLocalSearchCompletion) async -> NavigationDestination? {
        await searchGate.executeForeground {
            let request = MKLocalSearch.Request(completion: completion)
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard let coordinate = response.mapItems.first?.placemark.coordinate else { return nil }
                return NavigationDestination(coordinate: coordinate, title: completion.title)
            } catch {
                return nil
            }
        }
    }
    
    func RequestUserLocation() {
        locationManager.RequestUserLocation()
    }
    
    /// Hitung rute jalan kaki asli dari lokasi user saat ini ke koordinat tujuan.
    /// Dipanggil setelah user tap "See Routes", supaya layar preview rute
    /// menampilkan jalur & estimasi yang beneran, bukan data sample.
        @MainActor
        func calculateWalkingRoute(to destination: CLLocationCoordinate2D) async {
            guard let origin = locationManager.userLocation?.coordinate else {
                calculatedRoutes = []
                return
            }
    
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = .walking
            request.requestsAlternateRoutes = true
    
            do {
                let response = try await MKDirections(request: request).calculate()
                calculatedRoutes = response.routes
            } catch {
                calculatedRoutes = []
            }
        }
    
    func GetCurrentWeather(for location: CLLocation) async {
        do {
            let weather = try await weatherService.weather(for: location)
            let current = weather.currentWeather
            
            self.temperature = "\(Int(current.temperature.value))°"
            self.feelsLike = "Feels like \(Int(current.apparentTemperature.value))°"
            self.uvIndex = Int(current.uvIndex.value)
            self.uvCategory = "\(current.uvIndex.category.description) UV Index"
            self.weatherSymbolName = current.symbolName
        } catch {
            return
        }
    }
    
    /// Menyelesaikan perhitungan jarak menggunakan JALUR BIASA (Background)
    @MainActor
    func resolveDistance(for completion: MKLocalSearchCompletion) async -> String {
        let key = completion.stableID
        if let cached = distanceCache[key] {
            return cached
        }
        
        var userLocation = locationManager.userLocation
        var attempts = 0
        while userLocation == nil && attempts < 10 {
            guard !Task.isCancelled else { return "—" }
            try? await Task.sleep(nanoseconds: 200_000_000)
            userLocation = locationManager.userLocation
            attempts += 1
        }
        guard !Task.isCancelled else { return "—" }
        guard let userLocation else { return "—" }
        
        let result = await searchGate.executeBackground {
            let request = MKLocalSearch.Request(completion: completion)
            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                guard !Task.isCancelled else { return "—" }
                guard let destination = response.mapItems.first?.placemark.location else { return "—" }
                let meters = userLocation.distance(from: destination)
                let text = self.formattedDistance(meters)
                self.distanceCache[key] = text
                return text
            } catch {
                return "—"
            }
        }
        
        return result ?? "—"
    }
    
    @MainActor
    func loadDistances(for results: [MKLocalSearchCompletion]) {
        distanceResolutionTask?.cancel()
        distanceResolutionTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for completion in results {
                    group.addTask {
                        guard !Task.isCancelled else { return }
                        _ = await self.resolveDistance(for: completion)
                    }
                }
            }
        }
    }

    func cachedDistance(for completion: MKLocalSearchCompletion) -> String {
        distanceCache[completion.stableID] ?? "…"
    }

    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
    
    private func loadRouteGraph() {
        guard let url = Bundle.main.url(forResource: "1400", withExtension: "json") else { return }
        do {
            let graph = try RouteGraph(jsonURL: url)
            self.routeGraph = graph
            self.routePlanner = RoutePlanner(graph: graph)
        } catch {
            // handle/log if you want visibility here
        }
    }
    
    @MainActor
    func calculateShadedWalkingRoute(to destination: CLLocationCoordinate2D) async {
        guard let origin = locationManager.userLocation?.coordinate else {
            shadedRoute = nil
            return
        }
        guard let graph = routeGraph, let planner = routePlanner else {
            // Graph missing entirely — fall back to plain Apple Maps walking route
            await legacyAppleMapsRoute(from: origin, to: destination)
            return
        }
        
        let startSnap = graph.snap(to: origin)
        let endSnap = graph.snap(to: destination)
        
        guard case .snapped(let sNode, _) = startSnap,
              case .snapped(let eNode, _) = endSnap else {
            await legacyAppleMapsRoute(from: origin, to: destination)
            return
        }
        
        async let lead = nativeWalkingLeg(from: origin, to: sNode.coordinate)
        async let trail = nativeWalkingLeg(from: eNode.coordinate, to: destination)
        let (leadLeg, trailLeg) = await (lead, trail)
        
        do {
            let core = try planner.shadiestRoute(from: sNode.id, to: eNode.id)
            shadedRoute = stitch(lead: leadLeg, core: core, trail: trailLeg)
        } catch {
            await legacyAppleMapsRoute(from: origin, to: destination)
        }
    }
    
    /// Bridges origin/destination to the graph, exactly like NavigateViewModel does —
    /// this is the "apple map" leg on either end of the "json" core.
    private func nativeWalkingLeg(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> RouteResult? {
        guard CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude)) > snapThresholdMeters
        else { return nil }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking
        
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            return RouteResult(
                nodeIds: [],
                coordinates: route.polyline.coordinates,
                totalLength: route.distance,
                totalWeight: 0,
                estimatedTime: route.expectedTravelTime,
                label: "Approach Leg"
            )
        } catch {
            return nil
        }
    }
    
    private func stitch(lead: RouteResult?, core: RouteResult, trail: RouteResult?) -> RouteResult {
        var coords = lead?.coordinates ?? []
        coords += core.coordinates
        if let trail { coords += trail.coordinates }
        return RouteResult(
            nodeIds: core.nodeIds,
            coordinates: coords,
            totalLength: (lead?.totalLength ?? 0) + core.totalLength + (trail?.totalLength ?? 0),
            totalWeight: core.totalWeight,
            estimatedTime: (lead?.estimatedTime ?? 0) + core.estimatedTime + (trail?.estimatedTime ?? 0),
            label: core.label,
            shadedLength: core.shadedLength
        )
    }
    
    /// Fallback when the area isn't in the graph at all — plain Apple Maps route.
    @MainActor
    private func legacyAppleMapsRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { shadedRoute = nil; return }
            shadedRoute = RouteResult(
                nodeIds: [], coordinates: route.polyline.coordinates,
                totalLength: route.distance, totalWeight: 0,
                estimatedTime: route.expectedTravelTime, label: "Apple Maps (no graph coverage)"
            )
        } catch {
            shadedRoute = nil
        }
    }
}
