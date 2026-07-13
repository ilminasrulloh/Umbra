//
//  NavigateViewModel.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 01/07/26.
//

import Foundation
import SwiftUI
//import _MapKit_SwiftUI
import MapKit
import Combine

@MainActor
@Observable
final class NavigateViewModel: NSObject {
    let mapViewModel = MapViewModel()
    var navigationRouteResult: RouteResult?
    var camera: MapCameraPosition = .automatic
    var currentStepIndex: Int = 0
    private(set) var traveledDistance: CLLocationDistance = 0
    var distanceToNextStep: CLLocationDistance = 0
    var isNavigating = false
    var errorMessage: String?
    
    var didArrive = false
    var isFollowingUser = true
    
    var currentSegments: [RouteSegment] = []
    var currentEnv: String? = ""
    var showToast = false
    var toastMessage: String = ""
    var toastIcon: String = ""
    
    var minutesOfSunAvoided: Int? {
        guard let arrivalSummary, arrivalSummary.totalLength > 0 else { return nil }
        let shadedFraction = arrivalSummary.shadedLength / arrivalSummary.totalLength
        let minutes = shadedFraction * arrivalSummary.estimatedTimeMinutes
        return max(1, Int(minutes.rounded()))
    }
    
    var activeSteps: [NavigationStep] {
        var result: [NavigationStep] = []
        var previousDistance: CLLocationDistance = 0
        for maneuver in maneuvers {
            let segmentLength = max(maneuver.distanceFromStart - previousDistance, 0)
            result.append(NavigationStep(
                instructions: maneuver.instruction,
                distance: segmentLength,
                coordinate: maneuver.coordinate,
                entranceImageName: entranceImageName(for: maneuver)
            ))
            previousDistance = maneuver.distanceFromStart
        }
        return result
    }

    private let buildingEntranceImages: [String: String] = [:]

    /// nodeId gedung yang SUDAH punya foto dummy ("entranceDummy"). Cara isinya:
    /// 1. Jalankan app di device/simulator, mulai navigasi ke rute yang lewat gedung itu.
    /// 2. Lihat console — cari log "🚪 Enter the Building — nodeId: ..." (dicetak dari
    ///    `buildManeuvers`), catat nodeId yang muncul.
    /// 3. Tempel nodeId itu ke Set di bawah ini. Ulangi untuk tiap rute/gedung yang mau
    ///    dikasih foto dummy dulu, sisanya (belum ada di Set) tidak akan menampilkan foto.
    private let nodeIdsWithDummyEntranceImage: Set<String> = []

    private let dummyEntranceImageName: String? = "entranceDummy"

    private func entranceImageName(
        for maneuver: (instruction: String, coordinate: CLLocationCoordinate2D, distanceFromStart: CLLocationDistance, nodeId: String?)
    ) -> String? {
        guard let nodeId = maneuver.nodeId else { return nil }
        if let mapped = buildingEntranceImages[nodeId] {
            return mapped
        }
        if maneuver.instruction == "Enter the Building", nodeIdsWithDummyEntranceImage.contains(nodeId) {
            return dummyEntranceImageName
        }
        return nil
    }
    
    var remainingDistance: CLLocationDistance {
        guard let navigationRouteResult else { return 0 }
        let total = cumulativeDistances.last ?? navigationRouteResult.totalLength
        return max(total - traveledDistance, 0)
    }
    
    var remainingTravelTime: TimeInterval {
        guard let navigationRouteResult, navigationRouteResult.totalLength > 0 else { return 0 }
        let fraction = remainingDistance / navigationRouteResult.totalLength
        return navigationRouteResult.estimatedTime * fraction
    }
    
    var estimatedArrivalDate: Date {
        Date().addingTimeInterval(remainingTravelTime)
    }
    
    /// Radius kedatangan dalam 20 meter sesuai kebutuhan produk,
    /// supaya navigasi otomatis selesai begitu user mendekati tujuan tanpa harus berdiri
    /// TEPAT di titik koordinatnya (yang nyaris mustahil dengan akurasi GPS biasa).
    let arrivalRadiusMeters: CLLocationDistance = 20
    
    /// Snapshot rute terakhir SEBELUM `stopNavigation()` membersihkannya — dipakai
    /// untuk menghitung statistik "menit terik matahari yang dihindari" di sheet kedatangan.
    private(set) var arrivalSummary: RouteResult?
    
    /// Titik tujuan asli (bukan hasil snap ke graph) — disimpan terpisah supaya
    /// deteksi "sudah sampai" selalu dibandingkan ke titik yang benar-benar diminta user,
    /// bukan ke titik terakhir polyline (yang bisa sedikit berbeda karena stitching).
    private var destinationCoordinate: CLLocationCoordinate2D?
    
    /// Estimasi menit "waktu di bawah sinar matahari" yang berhasil dihindari sepanjang
    /// rute yang baru saja selesai — dipakai teks di sheet kedatangan. `nil` kalau belum
    /// ada rute yang selesai (mis. tampilan preview sebelum navigasi pertama dimulai).
    
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
    /// makin besar = makin responsif tapi makin terasa patah. 0.12–0.15 biasanya pas untuk jalan kaki.
    private let smoothingFactor: Double = 0.12
    
    /// Harus sinkron dengan cap yang sama di `MapViewModel.routeOptions` (maks 2 shaded
    /// slot: "shaded" + "shaded2" — sisa 1 slot dari total maks 3 dipakai "fastest").
    private let maxShadedRouteSlots = 2
    // MARK: - User camera override
    /// Selama ini `true`, `applyCamera()` boleh menimpa binding `camera`. Begitu user
    /// mulai gesture (pan/pinch) di peta, ini di-set `false` supaya loop kamera BERHENTI
    /// menimpa hasil gesture tsb. Tanpa ini, tiap tick (33ms) langsung "menarik paksa"
    /// kamera kembali ke posisi navigasi, sehingga zoom/pan terasa tidak berfungsi sama sekali.
    private var followResumeTask: Task<Void, Never>?
    /// Berapa lama menunggu sejak gesture terakhir sebelum kamera otomatis kembali "mengikuti" user.
    private let followResumeDelay: TimeInterval = 4.0
    
    private var maneuvers: [(instruction: String, coordinate: CLLocationCoordinate2D, distanceFromStart: CLLocationDistance, nodeId: String?)] = []
    private var cumulativeDistances: [CLLocationDistance] = []
    
    private(set) var selectedKind: String = "shaded"
    private let routeManager: RouteManager
    
    private var lastEnv: String? = nil
    
    init(routeManager: RouteManager = RouteManager()) {
        self.routeManager = routeManager
        super.init()
    }
    
    // CAMERA SETTINGS
    
    /// Panggil ini dari gesture handler di View saat user mulai men-drag/pinch peta.
    func pauseFollowingCamera() {
        isFollowingUser = false
        followResumeTask?.cancel()
        followResumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.followResumeDelay ?? 4.0) * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.isFollowingUser = true
        }
    }
    
    /// Panggil ini saat user menekan tombol "recenter" — langsung resume follow mode.
    func resumeFollowingCamera() {
        followResumeTask?.cancel()
        followResumeTask = nil
        isFollowingUser = true
    }
    
    /// Panggil ini saat carousel instruksi digeser ke step yang BUKAN step aktif —
    /// kamera berhenti mengikuti GPS user dan pindah (langsung, tanpa interpolasi,
    /// sama seperti `recenterCamera`) ke titik maneuver step tsb, supaya user bisa
    /// "intip" lokasi belokan yang ditunjukkan card. Top-down (pitch 0, heading utara)
    /// dipakai supaya tampilannya jelas beda dari POV navigasi normal.
    ///
    /// Begitu carousel kembali ke step yang sedang aktif, panggil `resumeFollowingCamera()`
    /// (bukan fungsi ini) supaya kamera kembali mengikuti posisi user secara live.
    func previewStep(at coordinate: CLLocationCoordinate2D) {
        followResumeTask?.cancel()
        followResumeTask = nil
        isFollowingUser = false
        camera = .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: 400,
                heading: 0,
                pitch: 0
            )
        )
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
        resumeFollowingCamera()
        targetCoordinate = coordinate
        targetHeading = heading
        displayedCoordinate = coordinate
        displayedHeading = heading
        applyCamera()
    }
    
    // NAVIGATION SETTINGS
    func startNavigation(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, kind: String) async {
        mapViewModel.pingWeatherManager = false
        selectedKind = kind
        destinationCoordinate = destination
        didArrive = false
        arrivalSummary = nil
        await calculateRoute(from: origin, to: destination, kind: kind)
        if navigationRouteResult != nil {
            isNavigating = true
            startCameraLoop()
        }
    }
    
    func stopNavigation() {
        mapViewModel.pingWeatherManager = true
        isNavigating = false
        navigationRouteResult = nil
        currentStepIndex = 0
        stopCameraLoop()
        displayedCoordinate = nil
        camera = .automatic
        followResumeTask?.cancel()
        followResumeTask = nil
        isFollowingUser = true
    }
    
    // ROUTING
    func calculateRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, kind: String) async {
        if kind == "fastest" {
            await calculateNativeRoute(from: origin, to: destination)
        } else {
            await calculateShadedRoute(from: origin, to: destination, kind: kind)
        }
    }
    
    func calculateShadedRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, kind: String = "shaded") async {
        let cores = await routeManager.calculateShadedRoute(from: origin, to: destination, maxRoutes: maxShadedRouteSlots)
        
        guard !cores.isEmpty else {
            return
        }
        
        let index = shadedRouteIndex(for: kind)
        let finalRoute = cores.indices.contains(index) ? cores[index] : cores[0]
        
        self.navigationRouteResult = finalRoute
        self.currentStepIndex = 0
        self.errorMessage = nil
        
        buildManeuvers(from: finalRoute)
    }
    
    func calculateNativeRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        if let result = await routeManager.nativeRouteResult(from: origin, to: destination) {
            self.navigationRouteResult = result
            self.currentStepIndex = 0
            self.errorMessage = nil
            
            buildManeuvers(from: result)
        } else {
            return
        }
    }
    
    func updateProgress(userLocation: CLLocation) {
        checkArrival(userLocation: userLocation)
        guard !didArrive else { return }
        guard !maneuvers.isEmpty, let navigationRouteResult else { return }
        
        var bestIdx = 0
        var bestDist = CLLocationDistance.greatestFiniteMagnitude
        for (i, coord) in navigationRouteResult.coordinates.enumerated() {
            let d = userLocation.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        let traveled = cumulativeDistances.indices.contains(bestIdx) ? cumulativeDistances[bestIdx] : 0
        traveledDistance = traveled   // <- BARU: simpan buat dipakai remainingDistance/remainingTravelTime
        
        guard isFollowingUser else { return }
        
        if let nextIdx = maneuvers.firstIndex(where: { $0.distanceFromStart >= traveled - 1 }), nextIdx != currentStepIndex {
            currentStepIndex = nextIdx
        }
        
        if currentStepIndex < maneuvers.count {
            let maneuverLocation = CLLocation(
                latitude: maneuvers[currentStepIndex].coordinate.latitude,
                longitude: maneuvers[currentStepIndex].coordinate.longitude
            )
            distanceToNextStep = userLocation.distance(from: maneuverLocation)
        }
    }
    
    /// Cek apakah user sudah melenceng dari garis rute lebih dari threshold (meter)
    func isOffRoute(_ location: CLLocation, threshold: CLLocationDistance = 50) -> Bool {
        //        guard let route else { return false }
        guard let navigationRouteResult, navigationRouteResult.coordinates.count > 1 else { return false }
        //        let polyline = route.polyline
        //        guard polyline.pointCount > 1 else { return false }
        
        let coords = navigationRouteResult.coordinates
        let userPoint = MKMapPoint(location.coordinate)
        //        let points = polyline.points()
        
        var minDistance = Double.greatestFiniteMagnitude
        //        for i in 0..<(polyline.pointCount - 1) {
        //            let d = distanceFromPoint(userPoint, toSegment: points[i], and: points[i + 1])
        //            minDistance = min(minDistance, d)
        //        }
        for i in 0..<(coords.count - 1) {
            let a = MKMapPoint(coords[i])
            let b = MKMapPoint(coords[i + 1])
            let d = distanceFromPoint(userPoint, toSegment: a, and: b)
            minDistance = min(minDistance, d)
        }
        return minDistance > threshold
    }
    
    func calculateDistance(a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
    
    func distanceFromPoint(_ point: MKMapPoint, toSegment a: MKMapPoint, and b: MKMapPoint) -> Double {
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
    
    // UPDATE USER ENV BASED ON LOCATION
    func updateEnvFromLocation(location: CLLocation) {
        guard let segment = nearestSegment(to: location.coordinate) else { return }
        
        currentEnv = segment.environment
        
        if segment.environment != lastEnv {
            handleEnvChange(to: segment.environment)
            lastEnv = segment.environment
        }
    }
    
    
    // SHADED ROUTE OPTIONS
    /// "shaded" -> 0, "shaded2" -> 1, "shaded3" -> 2, dst.
    private func shadedRouteIndex(for kind: String) -> Int {
        guard kind.hasPrefix("shaded") else { return 0 }
        let suffix = kind.dropFirst("shaded".count)
        guard !suffix.isEmpty, let n = Int(suffix) else { return 0 }
        return n - 1
    }
    
    // END NAVIGATION
    
    /// Dipanggil begitu `checkArrival` mendeteksi user sudah dalam radius tujuan.
    /// Menyimpan snapshot rute (untuk statistik di sheet kedatangan) sebelum
    /// `stopNavigation()` membersihkan state navigasi seperti biasa.
    private func handleArrival() {
        guard !didArrive else { return }
        arrivalSummary = navigationRouteResult
        didArrive = true
        stopNavigation()
    }
    
    
    
    /// Cek apakah user sudah berada dalam `arrivalRadiusMeters` dari titik tujuan.
    /// Dipanggil dari `updateProgress` tiap ada update lokasi baru selama navigasi.
    private func checkArrival(userLocation: CLLocation) {
        guard !didArrive, let destinationCoordinate else { return }
        let destinationLocation = CLLocation(
            latitude: destinationCoordinate.latitude,
            longitude: destinationCoordinate.longitude
        )
        if userLocation.distance(from: destinationLocation) <= arrivalRadiusMeters {
            handleArrival()
        }
    }
    
    private func buildManeuvers(from route: RouteResult) {
        cumulativeDistances = [0]
        let coords = route.coordinates
        let nodes = route.nodeIds
        
        print(nodes)
        
        for i in 1..<max(coords.count, 1) where i < coords.count {
            let d = calculateDistance(a: coords[i - 1], b: coords[i])
            cumulativeDistances.append(cumulativeDistances[i - 1] + d)
        }
        
        maneuvers = []
        
        func isIndoorNode(_ nodeId: String) -> Bool {
            if let nodeVal = Int(nodeId) {
                return ((-10008) ... (-10000)).contains(nodeVal)
            }
            return false
        }
        
        // MARK: - Lift nodes
        // Each entry: nodeId -> the floor name to announce when arriving fresh (not from its paired node).
        let liftFloorNames: [String: String] = [
            "-20008": "B2",
            "-20009": "G"
        ]
        
        /// Given a lift node, returns the *other* node in its pair (the only transition
        /// that counts as "still riding the lift" rather than entering/exiting it).
        func liftPartner(of nodeId: String) -> String? {
            switch nodeId {
            case "-20008": return "-20009"
            case "-20009": return "-20008"
            default: return nil
            }
        }
        
        func isLiftNode(_ nodeId: String) -> Bool {
            liftFloorNames[nodeId] != nil
        }
        
        var isCurrentlyInside = false
        
        for i in 0..<nodes.count {
            let currentNodeId = nodes[i]
            let previousNodeId = i > 0 ? nodes[i - 1] : nil
            let coord = i < coords.count ? coords[i] : (coords.last ?? .init())
            let dist = i < cumulativeDistances.count ? cumulativeDistances[i] : (cumulativeDistances.last ?? 0)
            
            // --- Lift handling ---
            if isLiftNode(currentNodeId) {
                let partner = liftPartner(of: currentNodeId)
                let arrivingFromPartner = (previousNodeId != nil && previousNodeId == partner)
                
                if !arrivingFromPartner {
                    // Fresh entry into the lift — announce destination floor.
                    let floorName = liftFloorNames[currentNodeId] ?? "?"
                    maneuvers.append((instruction: "Take lift to \(floorName)", coordinate: coord, distanceFromStart: dist, nodeId: currentNodeId))
                }
                // If arriving from its partner, we're mid-ride — no extra instruction needed here.
            } else if let previousNodeId, isLiftNode(previousNodeId) {
                // We just left a lift node and this new node is NOT its partner -> exiting the lift.
                let partner = liftPartner(of: previousNodeId)
                if currentNodeId != partner {
                    maneuvers.append((instruction: "Exit the lift", coordinate: coord, distanceFromStart: dist, nodeId: currentNodeId))
                }
            }
            
            // --- Existing indoor-building handling ---
            let indoor = isIndoorNode(currentNodeId)
            
            if !isCurrentlyInside && indoor {
                maneuvers.append((instruction: "Enter the Building", coordinate: coord, distanceFromStart: dist, nodeId: currentNodeId))
                isCurrentlyInside = true
                #if DEBUG
                print("🚪 Enter the Building — nodeId: \(currentNodeId), coord: \(coord.latitude), \(coord.longitude)")
                #endif
            } else if isCurrentlyInside && indoor {
                maneuvers.append((instruction: "Walk inside the Building", coordinate: coord, distanceFromStart: dist, nodeId: currentNodeId))
            } else if isCurrentlyInside && !indoor {
                maneuvers.append((instruction: "Exit the Building", coordinate: coord, distanceFromStart: dist, nodeId: currentNodeId))
                isCurrentlyInside = false
            }
        }
        
        for i in 1..<(coords.count - 1) {
            let b1 = bearing(coords[i - 1], coords[i])
            let b2 = bearing(coords[i], coords[i + 1])
            var delta = b2 - b1
            delta = (delta + 540).truncatingRemainder(dividingBy: 360) - 180
            if abs(delta) > 60 {
                let text = delta > 0 ? "Turn Right" : "Turn Left"
                maneuvers.append((instruction: text, coordinate: coords[i], distanceFromStart: cumulativeDistances[i], nodeId: nil))
            }
        }
        
        maneuvers.sort { $0.distanceFromStart < $1.distanceFromStart }
        
        maneuvers = mergeSimilarManeuvers(input: maneuvers)
        
        maneuvers.append((instruction: "Arrive at destination", coordinate: coords.last ?? .init(), distanceFromStart: cumulativeDistances.last ?? 0, nodeId: nil))
    }
    
    private func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }
    
    private func mergeSimilarManeuvers(input: [(instruction: String, coordinate: CLLocationCoordinate2D, distanceFromStart: CLLocationDistance, nodeId: String?)]) -> [(instruction: String, coordinate: CLLocationCoordinate2D, distanceFromStart: CLLocationDistance, nodeId: String?)] {
        
        let threshold: CLLocationDistance = 4
        
        guard !input.isEmpty else { return [] }
        
        var merged: [(instruction: String, coordinate: CLLocationCoordinate2D, distanceFromStart: CLLocationDistance, nodeId: String?)] = [input[0]]
        
        for current in input.dropFirst(){
            let last = merged[merged.count-1]
            
            
            if current.distanceFromStart - last.distanceFromStart < threshold {
                merged[merged.count-1] = (
                    instruction: last.instruction,
                    coordinate: last.coordinate,
                    distanceFromStart: last.distanceFromStart,
                    nodeId: last.nodeId
                )
            } else {
                merged.append(current)
            }
        }
        
        return merged
    }
    
    // CAMERA LOOP
    
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
    
    private func tickCamera() {
        guard let target = targetCoordinate, let current = displayedCoordinate else { return }
        
        let newLat = current.latitude + (target.latitude - current.latitude) * smoothingFactor
        let newLon = current.longitude + (target.longitude - current.longitude) * smoothingFactor
        displayedCoordinate = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
        
        displayedHeading = Self.lerpAngle(from: displayedHeading, to: targetHeading, factor: smoothingFactor)
        
        applyCamera()
    }
    
    private func applyCamera() {
        // User sedang pan/zoom manual -> jangan timpa, biar gesture-nya tidak "ketarik" balik.
        guard isFollowingUser else { return }
        guard let coordinate = displayedCoordinate else { return }
        camera = .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: 300,
                heading: displayedHeading,
                pitch: 45
            )
        )
    }
    
    private static func lerpAngle(from current: CLLocationDirection, to target: CLLocationDirection, factor: Double) -> CLLocationDirection {
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        
        var result = (current + delta * factor).truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result
    }
    
        // UPDATE USER ENV BASED ON LOCATION
//    func updateEnvFromLocation(location: CLLoation) {
//        guard let segment = nearestSegment(to: location.coordinate) else { return }
//
//        currentEnv = segment.environment
//
//        if segmend.environment != lastEnv {
//            handleEnvChange(to: segment.environment)
//            lastEnvironment = segment.environment
//        }
//    }
    
    private func nearestSegment(to coordinate: CLLocationCoordinate2D) -> RouteSegment? {
        let userLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return currentSegments.min(by: { seg1, seg2 in
            let d1 = seg1.coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: userLoc) }.min() ?? .infinity
            let d2 = seg2.coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: userLoc) }.min() ?? .infinity
            return d1 < d2
        })
    }
    
    private func handleEnvChange(to environment: String) {
        switch environment {
        case "shaded":
            toastMessage = "You are now in the shade"
            toastIcon = "⛱️"
        default:
            return
        }
        
        showToast = true
        
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { showToast = false }
        }
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
