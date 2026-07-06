//
//  LocationManager.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 05/07/26.
//

import Foundation
import Combine
import MapKit
import WeatherKit
import Observation

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    var userLocation: CLLocation?
    var heading: CLHeading?
    var userAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    var lastErrorMessage: String?
    
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        //manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 5 // update tiap user bergerak 5 meter
        manager.headingFilter = 1 // update tiap kompas berubah minimal 1°, kurangi noise sensor
    }
    
    func RequestUserLocation(){
        guard CLLocationManager.locationServicesEnabled() else {
            lastErrorMessage = "Location Services mati di level sistem. Aktifkan di Settings > Privacy & Security > Location Services."
            return
        }
        
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        case .denied, .restricted:
            lastErrorMessage = "Izin lokasi ditolak. Buka Settings > Privacy & Security > Location Services untuk mengaktifkan izin untuk app ini."
        @unknown default:
            break
        }
    }
    
    func start() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.userLocation = location
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading
        }
    }
    
    // Izin lokasi diubah oleh user
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.userAuthorizationStatus = manager.authorizationStatus
        
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            self.lastErrorMessage = nil
            self.start()
        case .denied, .restricted:
            self.lastErrorMessage = "Izin lokasi ditolak. Buka Settings > Privacy & Security > Location Services untuk mengaktifkan izin untuk app ini."
        default:
            break
        }
    }
    
    // Dipanggil kalau CoreLocation gagal mendapatkan lokasi (mis. tidak ada sinyal GPS)
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastErrorMessage = "Gagal mendapatkan lokasi: \(error.localizedDescription)"
        }
    }
}
