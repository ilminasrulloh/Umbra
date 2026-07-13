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
    var routeManager = RouteManager()
    
    var results: [MKLocalSearchCompletion] = []
    var nearbyResults: [MKMapItem] = []
    var temperature: Int = 2
    var uvIndex: Int = 1
    var feelsLike: Int = 3
    var weatherEmoji: String = "sun.max"
    
    var weatherText: String = "**Scorching hot** out there! 🥵"
    var weatherSuggestion: String = "Why sweat it? Pick our **Recommended Route** for the breeziest, most **comfortable walk**."
    var uvIndexText: String = "High"
    var itemReminderText: String = "Don't forget your **sunscreen** and a handy **umbrella**! ⛱️"
    
    let weatherService = WeatherService.shared
    private let completer = MKLocalSearchCompleter()
    
    var pingWeatherManager = true
    var userCurrentPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    var userOriginText = ""
    var userDestinationText = ""
    var showDestination = true
    
    var nativeRoutes: [MKRoute] = []
    var shadedRoutes: [RouteResult] = []
    
    var routeOptions: [RouteOption] {
        var options: [RouteOption] = []
        
        let plain = nativeRoutes.first
        
        // Buang shaded route yang sebenarnya sama aja sama rute standard Apple Maps.
        let distinctShaded = shadedRoutes.filter { shaded in
            guard let plain else { return true }
            let distanceDiff = abs(shaded.totalLength - plain.distance)
            let pointCountDiff = abs(shaded.coordinates.count - plain.polyline.pointCount)
            return !(distanceDiff < 5 && pointCountDiff < 2)
        }
        
        // Maks 3 rute total (termasuk standard) → maks 2 slot shaded.
        let cappedShaded = Array(distinctShaded.prefix(2))
        
        for (index, shaded) in cappedShaded.enumerated() where !shaded.coordinates.isEmpty {
            options.append(RouteOption(
                kind: index == 0 ? "shaded" : "shaded\(index + 1)",
                shadePercent: shaded.shadePercent,
                subtitle: index == 0
                ? (shaded.shadePercent >= 40 ? "Recommended - stays mostly shaded" : "Some sunshine along the way")
                : "Alternative shaded route",
                minutes: max(Int(shaded.estimatedTime / 60), 1),
                meters: Int(shaded.totalLength),
                isRecommended: index == 0))
        }
        
        if let plain {
            let isOnlyRoute = cappedShaded.isEmpty
            options.append(RouteOption(
                kind: "fastest",
                shadePercent: 0,
                subtitle: "Apple Maps Route",
                minutes: max(Int(plain.expectedTravelTime / 60), 1),
                meters: Int(plain.distance),
                isRecommended: isOnlyRoute))
        }
        
        return options
    }
    
    private var searchDebounceTask: Task<Void, Never>?
    private var distanceResolutionTask: Task<Void, Never>?
    private var sortTask: Task<Void, Never>?
    private var distanceCache: [String: String] = [:]
    
    private func shadedRouteIndex(for kind: String) -> Int? {
        switch kind {
        case "shaded": return 0
        case "shaded2": return 1
        default: return nil
        }
    }
    
    private let searchGate = SearchGate()
    
    
    override init() {
        super.init()
        initSearchCompleter()
    }
    
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
    
    @MainActor
    func calculateWalkingRoute(to destination: CLLocationCoordinate2D) async {
        guard let origin = locationManager.userLocation?.coordinate else {
            nativeRoutes = []
            return
        }
        nativeRoutes = await routeManager.calculateWalkingRoute(from: origin, to: destination)
    }
    
    @MainActor
    func calculateShadedRoute(to destination: CLLocationCoordinate2D) async {
        guard let origin = locationManager.userLocation?.coordinate else {
            nativeRoutes = []
            return
        }
        shadedRoutes = await routeManager.calculateShadedRoute(from: origin, to: destination, maxRoutes: 2)
    }
    
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
    
    func initSearchCompleter() {
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }
    
    func searchLocation(query: String) {
        searchDebounceTask?.cancel()
        
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
        sortTask?.cancel()
        sortTask = Task {
            await sortResultsToNearest()
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
    
    func getNearbyPlaces() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        guard let userLocation = locationManager.userLocation else { return }
        
        let request = MKLocalPointsOfInterestRequest(
            center: userLocation.coordinate, radius: 1000
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
                .foodMarket, .stadium,
                .hotel, .library,
                .school, .university,
                .fitnessCenter, .hospital
            ])
//        .restaurant, .cafe, .bakery,
        
        do {
            let response = try await MKLocalSearch(request: request).start()
            nearbyResults = response.mapItems
        } catch {
            
        }
    }
    
    func sortResultsToNearest() async {
        guard let userLocation = locationManager.userLocation else { return }
        
        // Cuma geocode sebagian kecil hasil teratas — cukup buat kebutuhan sorting,
        // tanpa nge-flood MKLocalSearch kalau hasil pencariannya banyak.
        let maxResultsToSort = 6
        let snapshot = Array(results.prefix(maxResultsToSort))
        
        let resultAndDistance: [(completion: MKLocalSearchCompletion, distance: CLLocationDistance)] = await withTaskGroup(of: (MKLocalSearchCompletion, CLLocationDistance)?.self) { group in
            for completion in snapshot {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    return await self.searchGate.executeBackground {
                        guard !Task.isCancelled else { return nil }
                        let request = MKLocalSearch.Request(completion: completion)
                        let search = MKLocalSearch(request: request)
                        
                        // Kalau task ini dicancel (misalnya user ngetik lagi),
                        // beneran hentikan request-nya, bukan cuma diabaikan.
                        return await withTaskCancellationHandler {
                            do {
                                let response = try await search.start()
                                guard !Task.isCancelled else { return nil }
                                guard let coordinate = response.mapItems.first?.placemark.coordinate else { return nil }
                                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                                return (completion, userLocation.distance(from: location))
                            } catch {
                                return nil
                            }
                        } onCancel: {
                            search.cancel()
                        }
                    } ?? nil
                }
            }
            var collected: [(MKLocalSearchCompletion, CLLocationDistance)] = []
            for await result in group {
                if let result { collected.append(result) }
            }
            return collected
        }
        
        guard !Task.isCancelled else { return }
        
        let sorted = resultAndDistance
            .sorted { $0.distance < $1.distance }
            .map { $0.completion }
        
        // Hasil yang nggak ikut di-geocode (di luar prefix) tetap ditampilkan,
        // ditempel di belakang, biar list nggak keliatan "hilang" sebagian.
        let sortedIDs = Set(sorted.map { $0.stableID })
        let remainder = results.filter { !sortedIDs.contains($0.stableID) }
        
        self.results = sorted + remainder
    }
    
    func requestUserLocation() {
        locationManager.requestUserLocation()
    }
    
    func getCurrentWeather(for location: CLLocation) async {
        do {
            let weather = try await weatherService.weather(for: location)
            let current = weather.currentWeather
            
            self.temperature = Int(current.temperature.value)
            self.feelsLike = Int(current.apparentTemperature.value)
            self.uvIndex = Int(current.uvIndex.value)
            self.weatherEmoji = current.symbolName
            
            updateWeatherValue()
        } catch {
            return
        }
    }
    
    func updateWeatherValue(){
        if self.temperature >= 30 {
            self.weatherText = "**Scorching hot** out there! 🥵"
            self.weatherSuggestion = "Why sweat it? Pick our **Recommended Route** for the breeziest, most **comfortable walk**."
            self.itemReminderText = "Don't forget your **sunscreen** and a handy **umbrella**! ⛱️"
        } else if self.temperature <= 18 {
            self.weatherText = "It's **kinda cold** today! 🫨"
            self.weatherSuggestion = "**Any routes** are fine today!"
            self.itemReminderText = "Dress **warmly** and bring your **umbrella**! 🧥"
        } else {
            self.weatherText = "The weather is **nice** today! ☺️"
            self.weatherSuggestion = "Pick **Recommended Route** for more Comfort"
            self.itemReminderText = "Don't forget to use your **sunscreen** 🧴"
        }
        
        if self.uvIndex >= 8 {
            self.uvIndexText = "Extreme"
        } else if self.uvIndex >= 6 {
            self.uvIndexText = "High"
        } else if self.uvIndex >= 3 {
            self.uvIndexText = "Moderate"
        } else {
            self.uvIndexText = "Low"
        }
    }
    
    func cachedDistance(for completion: MKLocalSearchCompletion) -> String {
        distanceCache[completion.stableID] ?? "…"
    }
    
    func midpointCoordinate(for kind: String) -> CLLocationCoordinate2D? {
        switch kind {
        case "fastest":
            guard let coords = nativeRoutes.first?.polyline.coordinates, !coords.isEmpty else { return nil }
            return coords[coords.count / 2]
        default:
            guard let index = shadedRouteIndex(for: kind),
                  let coords = shadedRoutes[safe: index]?.coordinates, !coords.isEmpty else { return nil }
            return coords[coords.count / 2]
        }
    }
    
    
    @MainActor
    private func legacyAppleMapsRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { shadedRoutes = []; return }
            shadedRoutes = [RouteResult(
                nodeIds: [], coordinates: route.polyline.coordinates,
                totalLength: route.distance, totalWeight: 0,
                estimatedTime: route.expectedTravelTime, label: "Apple Maps (no graph coverage)", segments: []
            )]
        } catch {
            shadedRoutes = []
        }
    }
    
    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
}

extension MKLocalSearchCompletion {
    var stableID: String { "\(title)|\(subtitle)" }
}

extension MKMapItem {
    var stableID: String { "\(name)" }
    
    static func == (lhs: MKMapItem, rhs: MKMapItem) -> Bool {
        lhs.placemark.coordinate.latitude == rhs.placemark.coordinate.latitude &&
        lhs.placemark.coordinate.longitude == rhs.placemark.coordinate.longitude &&
        lhs.name == rhs.name
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
