//
//  NavigateViewModel.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 01/07/26.
//

import Foundation
import SwiftUI
import _MapKit_SwiftUI
import MapKit
import Combine


@MainActor
@Observable
final class NavigateViewModel: NSObject {

    var route: MKRoute?
    var camera: MapCameraPosition = .automatic
    var currentStepIndex: Int = 0
    var distanceToNextStep: CLLocationDistance = 0
    var isNavigating = false
    var errorMessage: String?

    /// Instruksi yang benar-benar punya teks (step pertama biasanya kosong)
    var activeSteps: [MKRoute.Step] {
        route?.steps.filter { !$0.instructions.isEmpty } ?? []
    }

    /// Estimasi sisa jarak dari instruksi yang sedang aktif sampai tujuan akhir.
    /// Dijumlah dari panjang tiap step yang tersisa — pendekatan sederhana untuk demo,
    /// bukan jarak presisi dari posisi persis user saat ini.
    var remainingDistance: CLLocationDistance {
        let steps = activeSteps
        guard currentStepIndex < steps.count else { return 0 }
        return steps[currentStepIndex...].reduce(0) { $0 + $1.distance }
    }

    /// Estimasi sisa waktu tempuh, dihitung proporsional terhadap sisa jarak
    /// dibanding total jarak & waktu tempuh rute (MKRoute tidak menyediakan estimasi per-step).
    var remainingTravelTime: TimeInterval {
        guard let route, route.distance > 0 else { return 0 }
        let fraction = remainingDistance / route.distance
        return route.expectedTravelTime * fraction
    }

    var estimatedArrivalDate: Date {
        Date().addingTimeInterval(remainingTravelTime)
    }

    // MARK: - Camera smoothing
    /// Nilai "sumber kebenaran" dari GPS/kompas — bisa datang tidak teratur & noisy
    private var targetCoordinate: CLLocationCoordinate2D?
    private var targetHeading: CLLocationDirection = 0

    /// Nilai yang benar-benar dipakai kamera — bergerak sedikit demi sedikit menuju target
    /// tiap tick, bukan langsung "melompat". Inilah yang bikin gerakannya halus.
    private var displayedCoordinate: CLLocationCoordinate2D?
    private var displayedHeading: CLLocationDirection = 0

    private var cameraTimer: AnyCancellable?
    /// 30x per detik — cukup halus secara visual, tanpa terlalu boros baterai
    private let cameraTickInterval: TimeInterval = 1.0 / 30.0
    /// Porsi jarak ke target yang ditempuh tiap tick. Makin kecil = makin halus tapi makin "lag" mengikuti;
    /// makin besar = makin responsif tapi makin terasa patah. 0.15–0.2 biasanya pas untuk mobil.
    private let smoothingFactor: Double = 0.15
    
    func startNavigation(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        await calculateRoute(from: origin, to: destination)
        if route != nil {
            isNavigating = true
            startCameraLoop()
        }
    }

    func stopNavigation() {
        isNavigating = false
        route = nil
        currentStepIndex = 0
        stopCameraLoop()
        displayedCoordinate = nil // biar navigasi berikutnya snap dari posisi baru, bukan interpolasi dari posisi lama
        camera = .automatic
    }

    func calculateRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        request.requestsAlternateRoutes = false

        do {
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()
            guard let newRoute = response.routes.first else {
                errorMessage = "Rute tidak ditemukan"
                return
            }
            self.route = newRoute
            self.currentStepIndex = 0
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Gagal menghitung rute: \(error.localizedDescription)"
        }
    }

    /// Dipanggil setiap ada update lokasi user untuk maju ke instruksi berikutnya
    func updateProgress(userLocation: CLLocation) {
        let steps = activeSteps
        guard currentStepIndex < steps.count else { return }

        let step = steps[currentStepIndex]
        guard step.polyline.pointCount > 0 else { return }

        let stepCoordinate = step.polyline.points()[0].coordinate
        let stepLocation = CLLocation(latitude: stepCoordinate.latitude, longitude: stepCoordinate.longitude)
        let distance = userLocation.distance(from: stepLocation)
        distanceToNextStep = distance

        // Kalau sudah dekat (<25m) dengan titik instruksi, lanjut ke step berikutnya
        if distance < 25, currentStepIndex < steps.count - 1 {
            currentStepIndex += 1
        }
    }

    /// Dipanggil setiap ada data baru dari GPS/kompas. Ini TIDAK langsung menggerakkan kamera —
    /// cuma update "target" tujuan. Kamera yang sebenarnya digerakkan pelan-pelan oleh `tickCamera()`
    /// lewat timer, supaya hasilnya halus walau data GPS/kompas datangnya tidak teratur & noisy.
    func setCameraTarget(coordinate: CLLocationCoordinate2D, heading: CLLocationDirection) {
        targetCoordinate = coordinate
        targetHeading = heading

        // Frame pertama: langsung snap ke posisi awal, tidak ada posisi lama untuk diinterpolasi dari situ
        if displayedCoordinate == nil {
            displayedCoordinate = coordinate
            displayedHeading = heading
            applyCamera()
        }
    }

    /// Dipakai tombol "recenter" — langsung pindah kamera seketika (tanpa interpolasi),
    /// karena ini aksi eksplisit dari user yang mengharapkan respons instan.
    func recenterCamera(to coordinate: CLLocationCoordinate2D, heading: CLLocationDirection) {
        targetCoordinate = coordinate
        targetHeading = heading
        displayedCoordinate = coordinate
        displayedHeading = heading
        applyCamera()
    }
    
    /// Cek apakah user sudah melenceng dari garis rute lebih dari threshold (meter)
    func isOffRoute(_ location: CLLocation, threshold: CLLocationDistance = 50) -> Bool {
        guard let route else { return false }
        let polyline = route.polyline
        guard polyline.pointCount > 1 else { return false }

        let userPoint = MKMapPoint(location.coordinate)
        let points = polyline.points()

        var minDistance = Double.greatestFiniteMagnitude
        for i in 0..<(polyline.pointCount - 1) {
            let d = distanceFromPoint(userPoint, toSegment: points[i], and: points[i + 1])
            minDistance = min(minDistance, d)
        }
        return minDistance > threshold
    }
    
}

private extension NavigateViewModel {
    private func startCameraLoop() {
        stopCameraLoop()
        cameraTimer = Timer.publish(every: cameraTickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tickCamera()
            }
    }

    private func stopCameraLoop() {
        cameraTimer?.cancel()
        cameraTimer = nil
    }

    /// Satu langkah interpolasi: gerakkan `displayed...` sedikit lebih dekat ke `target...`.
    /// Dipanggil terus-menerus di frame rate tetap selama navigasi berjalan.
    private func tickCamera() {
        guard let target = targetCoordinate, let current = displayedCoordinate else { return }

        let newLat = current.latitude + (target.latitude - current.latitude) * smoothingFactor
        let newLon = current.longitude + (target.longitude - current.longitude) * smoothingFactor
        displayedCoordinate = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)

        displayedHeading = Self.lerpAngle(from: displayedHeading, to: targetHeading, factor: smoothingFactor)

        applyCamera()
    }

    private func applyCamera() {
        guard let coordinate = displayedCoordinate else { return }
        // Set langsung TANPA withAnimation — animasinya sudah "dibuat" secara manual
        // lewat interpolasi tiap tick di atas. Kalau dibungkus withAnimation lagi,
        // animasi baru akan menabrak animasi sebelumnya dan malah jadi patah-patah.
        camera = .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: 600,
                heading: displayedHeading,
                pitch: 60
            )
        )
    }

    /// Interpolasi sudut yang menangani wraparound 0°/360° dengan benar,
    /// supaya kamera selalu berputar lewat jalur terpendek (bukan muter jauh
    /// saat heading lompat dari 359° ke 1°, misalnya).
    private static func lerpAngle(from current: CLLocationDirection, to target: CLLocationDirection, factor: Double) -> CLLocationDirection {
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }

        var result = (current + delta * factor).truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result
    }

    /// Jarak titik ke segmen garis (proyeksi tegak lurus, di-clamp ke ujung segmen)
    private func distanceFromPoint(_ point: MKMapPoint, toSegment a: MKMapPoint, and b: MKMapPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y

        if dx == 0 && dy == 0 {
            return point.distance(to: a)
        }

        let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)
        let clampedT = max(0, min(1, t))
        let projected = MKMapPoint(x: a.x + clampedT * dx, y: a.y + clampedT * dy)
        return point.distance(to: projected)
    }
}
