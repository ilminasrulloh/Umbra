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
    
    func MoveToSelectedLocation(completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        MKLocalSearch(request: request).start { response, _ in
            guard let coordinate = response?.mapItems.first?.placemark.coordinate else { return }
            
            //            Task { @MainActor in
            //                await assignCoordinate(coordinate, to: activeField, title: completion.title)
            //            }
            
        }
    }
    
    // Get Location
    func RequestUserLocation() {
        locationManager.RequestUserLocation()
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
}
