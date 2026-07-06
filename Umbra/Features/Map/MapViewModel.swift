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
    
    
    // Search Completer
    override init() {
        super.init()
        InitSearchCompleter()
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
    
}
