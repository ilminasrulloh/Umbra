//
//  LocationManager.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 05/07/26.
//

import Foundation
import SwiftUI
import Combine
import MapKit
import WeatherKit

@Observable()
class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    var userLocation: CLLocation?
    var userAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func RequestUserLocation(){
        manager.requestWhenInUseAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        self.userLocation = location
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.userAuthorizationStatus = manager.authorizationStatus
        
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            
        default:
            break
        }
        
        
    }
}
