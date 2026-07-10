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
    
    var shadedRouteResult: RouteResult?
    var camera: MapCameraPosition = .automatic
    var currentStepIndex: Int = 0
    private(set) var traveledDistance: CLLocationDistance = 0
    var distanceToNextStep: CLLocationDistance = 0
    var isNavigating = false
    var errorMessage: String?

    var didArrive = false
    var isFollowingUser = true
    
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
                coordinate: maneuver.coordinate
            ))
            previousDistance = maneuver.distanceFromStart
        }
        return result
    }
    
    var remainingDistance: CLLocationDistance {
        guard let shadedRouteResult else { return 0 }
        let total = cumulativeDistances.last ?? shadedRouteResult.totalLength
        return max(total - traveledDistance, 0)
    }
    
    var remainingTravelTime: TimeInterval {
        guard let shadedRouteResult, shadedRouteResult.totalLength > 0 else { return 0 }
        let fraction = remainingDistance / shadedRouteResult.totalLength
        return shadedRouteResult.estimatedTime * fraction
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
    
    private var graph: RouteGraph?
    private var planner: RoutePlanner?
    
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
    
    private let snapThresholdMeters: CLLocationDistance = 20
    
    override init() {
        super.init()
        loadGraph()
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
        selectedKind = kind
        destinationCoordinate = destination
        didArrive = false
        arrivalSummary = nil
        await calculateRoute(from: origin, to: destination, kind: kind)
        if shadedRouteResult != nil {
            isNavigating = true
            startCameraLoop()
        }
    }
    
    func stopNavigation() {
        isNavigating = false
        shadedRouteResult = nil
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
        guard let graph, let planner else {
            errorMessage = "Route graph (1400.json) failed to load — check it's included in the app bundle."
            return
        }
        
        let startSnap = graph.snap(to: origin)
        let endSnap = graph.snap(to: destination)
        
        guard case .snapped(let sNode, _) = startSnap, case .snapped(let eNode, _) = endSnap else {
            errorMessage = "Couldn't find any usable point in the route graph near your start/destination."
            return
        }
        
        async let lead = nativeWalkingLegIfNeeded(from: origin, to: sNode.coordinate)
        async let trail = nativeWalkingLegIfNeeded(from: eNode.coordinate, to: destination)
        let (leadLeg, trailLeg) = await (lead, trail)
        
        do {
            // Sama seperti MapViewModel: minta sampai `maxShadedRouteSlots` rute teduh yang
            // berbeda, terus ambil index yang sesuai kind-nya ("shaded" -> 0, "shaded2" -> 1, dst).
            let cores = try planner.shadiestRoutes(from: sNode.id, to: eNode.id, maxRoutes: maxShadedRouteSlots)
            let index = shadedRouteIndex(for: kind)
            
            // Kalau alternate yang diminta ternyata nggak ada (misal cuma 1 shaded route yang
            // valid), fallback ke rute teduh utama daripada gagal total.
            guard let core = cores.indices.contains(index) ? cores[index] : cores.first else {
                self.errorMessage = "No connected path exists in the route graph between these two points."
                return
            }
            
            let finalRoute = stitch(lead: leadLeg, core: core, trail: trailLeg)
            
            self.shadedRouteResult = finalRoute
            self.currentStepIndex = 0
            self.errorMessage = nil
            buildManeuvers(from: finalRoute)
        } catch RoutePlannerError.noPathFound {
            self.errorMessage = "No connected path exists in the route graph between these two points."
        } catch {
            self.errorMessage = "Couldn't compute a route from the graph: \(error)"
        }
    }
    
    func calculateNativeRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                errorMessage = "Rute tidak ditemukan"
                return
            }
            let result = RouteResult(
                nodeIds: [],
                coordinates: route.polyline.coordinates,
                totalLength: route.distance,
                totalWeight: 0,
                estimatedTime: route.expectedTravelTime,
                label: "Fastest (Apple Maps)",
                segments: []
            )
            self.shadedRouteResult = result
            self.currentStepIndex = 0
            self.errorMessage = nil
            buildManeuvers(from: result)
        } catch {
            self.errorMessage = "Gagal menghitung rute: \(error.localizedDescription)"
        }
    }
    
    func updateProgress(userLocation: CLLocation) {
        checkArrival(userLocation: userLocation)
        guard !didArrive else { return }
        guard !maneuvers.isEmpty, let shadedRouteResult else { return }
        
        var bestIdx = 0
        var bestDist = CLLocationDistance.greatestFiniteMagnitude
        for (i, coord) in shadedRouteResult.coordinates.enumerated() {
            let d = userLocation.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        let traveled = cumulativeDistances.indices.contains(bestIdx) ? cumulativeDistances[bestIdx] : 0
        traveledDistance = traveled   // <- BARU: simpan buat dipakai remainingDistance/remainingTravelTime
        
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
        guard let shadedRouteResult, shadedRouteResult.coordinates.count > 1 else { return false }
        //        let polyline = route.polyline
        //        guard polyline.pointCount > 1 else { return false }
        
        let coords = shadedRouteResult.coordinates
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
        arrivalSummary = shadedRouteResult
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
    
    
    
    
    // GRAPH/JSON LOADING
    
    private func loadGraph() {
        guard let url = Bundle.main.url(forResource: "1400", withExtension: "json") else {
            errorMessage = "Could not find 1400.json in the app bundle — check Target Membership & Copy Bundle Resources."
            return
        }
        do {
            let loadedGraph = try RouteGraph(jsonURL: url)
            self.graph = loadedGraph
            self.planner = RoutePlanner(graph: loadedGraph)
        } catch {
            errorMessage = "Failed to load route graph: \(error.localizedDescription)"
        }
    }
    
    // STITCHING ROUTES
    
    /// Bridges the gap between an arbitrary point (user's real origin/destination)
    /// and the nearest graph node, using a short native MapKit walking leg. This is
    /// the ONLY place MapKit routing is used — the core route always comes from the JSON.
    private func nativeWalkingLegIfNeeded(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> RouteResult? {
        guard calculateDistance(a: from, b: to) > snapThresholdMeters else { return nil }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking
        
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let newRoute = response.routes.first else { return nil }
            return RouteResult(
                nodeIds: [],
                coordinates: newRoute.polyline.coordinates,
                totalLength: newRoute.distance,
                totalWeight: 0,
                estimatedTime: newRoute.expectedTravelTime,
                label: "Approach Leg",
                segments: []
            )
        } catch {
            return nil
        }
    }
    
    private func stitch(lead: RouteResult?, core: RouteResult, trail: RouteResult?) -> RouteResult {
        var coords = lead?.coordinates ?? []
        if let last = coords.last, let first = core.coordinates.first, calculateDistance(a: last, b: first) < 1 {
            coords.removeLast()
        }
        coords += core.coordinates
        
        if let trail {
            if let last = coords.last, let first = trail.coordinates.first, calculateDistance(a: last, b: first) < 1 {
                coords.removeLast()
            }
            coords += trail.coordinates
        }
        
        return RouteResult(
            nodeIds: core.nodeIds,
            coordinates: coords,
            totalLength: (lead?.totalLength ?? 0) + core.totalLength + (trail?.totalLength ?? 0),
            totalWeight: core.totalWeight,
            estimatedTime: (lead?.estimatedTime ?? 0) + core.estimatedTime + (trail?.estimatedTime ?? 0),
            label: core.label, segments: []
        )
    }
    
    // MANEUVERS
    
    /// The JSON graph doesn't carry instruction text like MKRoute.steps does, so we
    /// derive simple "turn left/right" maneuvers from bearing changes along the
    /// stitched polyline, same approach used in RouteMapView's NavigationSession.
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
        
        var isCurrentlyInside = false
        
        for i in 0..<nodes.count {
            let currentNodeId = nodes[i]
            let indoor = isIndoorNode(currentNodeId)
            
            if !isCurrentlyInside && indoor {
                let instruction = "Enter the Building"
                let coord = i < coords.count ? coords[i] : (coords.last ?? .init())
                let dist = i < cumulativeDistances.count ? cumulativeDistances[i] : (cumulativeDistances.last ?? 0)
                maneuvers.append((instruction: instruction, coordinate: coord, distanceFromStart: dist, nodeId: currentNodeId))
                isCurrentlyInside = true
            } else if isCurrentlyInside && indoor {
                let instruction = "Walk inside the Building"
                let coord = i < coords.count ? coords[i] : (coords.last ?? .init())
                let dist = i < cumulativeDistances.count ? cumulativeDistances[i] : (cumulativeDistances.last ?? 0)
                maneuvers.append((instruction: instruction, coordinate: coord, distanceFromStart: dist, nodeId: currentNodeId))
            } else if isCurrentlyInside && !indoor {
                let instruction = "Exit the Building"
                let coord = i < coords.count ? coords[i] : (coords.last ?? .init())
                let dist = i < cumulativeDistances.count ? cumulativeDistances[i] : (cumulativeDistances.last ?? 0)
                maneuvers.append((instruction: instruction, coordinate: coord, distanceFromStart: dist, nodeId: currentNodeId))
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
        maneuvers.append((instruction: "Arrive at destination", coordinate: coords.last ?? .init(), distanceFromStart: cumulativeDistances.last ?? 0, nodeId: nil))
    }
    
    private func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
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
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
