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

/// Tujuan yang dipilih user dari hasil pencarian, dipakai untuk trigger
/// presentasi `NavigateView` lewat `.fullScreenCover(item:)`.
struct NavigationDestination: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
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
    
    /// Diisi begitu user memilih salah satu hasil pencarian.
    /// MapView mengamati ini lewat `.fullScreenCover(item:)` untuk pindah ke NavigateView.
    var pendingNavigationDestination: NavigationDestination?
    
    /// Rute jalan kaki asli (hasil MKDirections) dari lokasi user ke tujuan yang dipilih.
    /// Dipakai untuk menggambar polyline di peta pada layar "preview rute" (DirectionsSheet).
    var calculatedRoutes: [MKRoute] = []
    var shadedRoute: RouteResult?
    
    private var routeGraph: RouteGraph?
    private var routePlanner: RoutePlanner?
    private let snapThresholdMeters: CLLocationDistance = 20
    
    
    // Search Completer
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
        guard !query.isEmpty else {
            results = []
            return
        }
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
    
    /// Resolve hasil pencarian (`MKLocalSearchCompletion`) jadi koordinat asli,
    /// lalu simpan sebagai tujuan yang siap dinavigasikan. Begitu properti ini terisi,
    /// MapView otomatis pindah ke NavigateView lewat `.fullScreenCover(item:)`.
    @MainActor
    func MoveToSelectedLocation(completion: MKLocalSearchCompletion) async {
        let request = MKLocalSearch.Request(completion: completion)
        do {
            let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKLocalSearch.Response, Error>) in
                MKLocalSearch(request: request).start { response, error in
                    if let response {
                        continuation.resume(returning: response)
                    } else {
                        continuation.resume(throwing: error ?? NSError(domain: "MapViewModel", code: -1))
                    }
                }
            }
            guard let coordinate = response.mapItems.first?.placemark.coordinate else { return }
            pendingNavigationDestination = NavigationDestination(
                coordinate: coordinate,
                title: completion.title
            )
        } catch {
            // Bisa ditambahkan penanganan error (mis. tampilkan alert) kalau diperlukan
        }
    }
    
    // Get Location
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
    
    // Get Current Weather
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
    
    /// calculate Distance
    
    func resolveDistance(for completion: MKLocalSearchCompletion) async -> String {
        guard let userLocation = locationManager.userLocation else { return "—" }
        
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            guard let destination = response.mapItems.first?.placemark.location else { return "—" }
            let meters = userLocation.distance(from: destination)
            return formattedDistance(meters)
            
        } catch {
            return "—"
        }
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
            let core = try planner.shadedRoute(from: sNode.id, to: eNode.id)
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
            label: core.label
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
