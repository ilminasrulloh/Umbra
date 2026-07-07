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
    
    private var searchDebounceTask: Task<Void, Never>?
    private var distanceCache: [String: String] = [:]
    private var distanceResolutionTask: Task<Void, Never>?

    // Menggunakan SearchGate baru dengan pembagian prioritas
    private let searchGate = SearchGate()
    
    override init() {
        super.init()
        InitSearchCompleter()
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
    
    @MainActor
    func calculateWalkingRoute(from originCoordinate: CLLocationCoordinate2D? = nil, to destination: CLLocationCoordinate2D) async {
        guard let origin = originCoordinate ?? locationManager.userLocation?.coordinate else {
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
}
