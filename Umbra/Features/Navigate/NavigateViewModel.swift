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

struct NavigationStep: Identifiable {
    let id = UUID()
    let instructions: String
    let distance: CLLocationDistance
}

struct RouteNode: Codable {
    let id: String
    let lat: Double
    let lon: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct EdgeCoordinate: Codable {
    let lat: Double
    let lon: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

enum EnvironmentType: String, Codable {
    case sunny
    case shaded
    case indoor
}

struct RouteEdge: Codable {
    let source: String
    let target: String
    let length: Double
    let weight: Double
    let environment: EnvironmentType
    let coordinates: [EdgeCoordinate]
    
    var shadeFactor: Double { weight / length }
}

struct RouteGraphData: Codable {
    let nodes: [RouteNode]
    let edges: [RouteEdge]
}

final class RouteGraph {
    private(set) var nodesById: [String: RouteNode] = [:]
    private var adjacency: [String: [RouteEdge]] = [:]
    
    init(data: RouteGraphData) {
        for node in data.nodes {
            nodesById[node.id] = node
        }
        for edge in data.edges {
            adjacency[edge.source, default: []].append(edge)
        }
    }
    
    convenience init(jsonURL: URL) throws {
        let raw = try Data(contentsOf: jsonURL)
        let decoded = try JSONDecoder().decode(RouteGraphData.self, from: raw)
        self.init(data: decoded)
    }
    
    func neighbors(of nodeId: String) -> [RouteEdge] {
        adjacency[nodeId] ?? []
    }
}

extension RouteGraph {
    /// Diagonal size of the node cloud, in meters. Used to derive a sensible snap
    /// radius automatically instead of hardcoding a number that only fits one dataset.
    var approximateSpanMeters: CLLocationDistance? {
        let coords = nodesById.values.map { $0.coordinate }
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let corner1 = CLLocation(latitude: lats.min()!, longitude: lons.min()!)
        let corner2 = CLLocation(latitude: lats.max()!, longitude: lons.max()!)
        return corner1.distance(from: corner2)
    }
    
    enum SnapResult {
        case snapped(RouteNode, distance: CLLocationDistance)
        case tooFar(nearest: RouteNode, distance: CLLocationDistance, limit: CLLocationDistance)
        case empty
    }
    
    /// Snaps a coordinate to the nearest node in the graph. `maxDistance` is intentionally
    /// generous here (see NavigateViewModel.snapLimit) because we WANT snapping to succeed
    /// even far outside the graph's own footprint — `stitch()` will bridge the gap with a
    /// native walking leg. This is only a safety valve against snapping to a node literally
    /// oceans away when the graph itself is tiny/degenerate.
    func snap(to coordinate: CLLocationCoordinate2D, maxDistance: CLLocationDistance? = nil) -> SnapResult {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let closest = nodesById.values.min(by: {
            CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: target) <
                CLLocation(latitude: $1.lat, longitude: $1.lon).distance(from: target)
        }) else { return .empty }
        
        let distance = CLLocation(latitude: closest.lat, longitude: closest.lon).distance(from: target)
        let limit = maxDistance ?? min(max((approximateSpanMeters ?? 1600) * 3, 3000), 20000)
        
        return distance <= limit ? .snapped(closest, distance: distance) : .tooFar(nearest: closest, distance: distance, limit: limit)
    }
}

// MARK: - Route result

struct RouteResult {
    let nodeIds: [String]
    let coordinates: [CLLocationCoordinate2D]
    let totalLength: Double
    let totalWeight: Double
    let estimatedTime: TimeInterval
    let label: String
    var shadedLength: Double = 0
    
    var totalLengthKm: Double { totalLength / 1000 }
    var estimatedTimeMinutes: Double { estimatedTime / 60 }
    
    var shadePercent: Int {
        guard totalLength > 0 else { return 0 }
        return Int((shadedLength/totalLength) * 100)
    }
}

// MARK: - Planner

enum RoutePlannerError: Error {
    case startNotFound
    case endNotFound
    case noPathFound
}

final class RoutePlanner {
    private let graph: RouteGraph
    private let walkingSpeed: Double
    
    init(graph: RouteGraph, walkingSpeed: Double = 1.4) {
        self.graph = graph
        self.walkingSpeed = walkingSpeed
    }
    
    private func buildResult(from edges: [RouteEdge], label: String) -> RouteResult {
        guard let first = edges.first else {
            return RouteResult(nodeIds: [], coordinates: [], totalLength: 0, totalWeight: 0, estimatedTime: 0, label: label)
        }
        
        var nodeIds = [first.source]
        var coordinates: [CLLocationCoordinate2D] = []
        var totalLength = 0.0
        var totalWeight = 0.0
        var shadedLength = 0.0
        
        for edge in edges {
            nodeIds.append(edge.target)
            totalLength += edge.length
            totalWeight += edge.weight
            
            if edge.environment != .sunny {
                shadedLength += edge.length
            }
                
            let coords = edge.coordinates.map {$0.coordinate}
            
            if coordinates.isEmpty {
                coordinates.append(contentsOf: coords)
            } else {
                coordinates.append(contentsOf: coords.dropFirst())
            }
        }
        
        return RouteResult(
            nodeIds: nodeIds,
            coordinates: coordinates,
            totalLength: totalLength,
            totalWeight: totalWeight,
            estimatedTime: totalLength/walkingSpeed,
            label: label,
            shadedLength: shadedLength)
    }
    
    private func dijkstra(from start: String, to end: String, cost: (RouteEdge) -> Double) throws -> [RouteEdge] {
        guard graph.nodesById[start] != nil else { throw RoutePlannerError.startNotFound }
        guard graph.nodesById[end] != nil else { throw RoutePlannerError.endNotFound }
        
        var distances: [String: Double] = [start: 0]
        var previousEdge: [String: RouteEdge] = [:]
        var visited: Set<String> = []
        
        while true {
            guard let current = distances
                .filter({ !visited.contains($0.key) })
                .min(by: { $0.value < $1.value })?.key
            else { break }
            
            if current == end { break }
            visited.insert(current)
            
            for edge in graph.neighbors(of: current) {
                guard !visited.contains(edge.target) else { continue }
                let newDist = distances[current]! + cost(edge)
                if newDist < (distances[edge.target] ?? .infinity) {
                    distances[edge.target] = newDist
                    previousEdge[edge.target] = edge
                }
            }
        }
        
        guard distances[end] != nil else { throw RoutePlannerError.noPathFound }
        
        var path: [RouteEdge] = []
        var currentId = end
        while let edge = previousEdge[currentId] {
            path.append(edge)
            currentId = edge.source
        }
        return path.reversed()
    }
    
//    private func buildResult(from edges: [RouteEdge], label: String) -> RouteResult {
//        guard let first = edges.first else {
//            return RouteResult(nodeIds: [], coordinates: [], totalLength: 0, totalWeight: 0, estimatedTime: 0, label: label)
//        }
//        
//        var nodeIds = [first.source]
//        var coordinates: [CLLocationCoordinate2D] = []
//        var totalLength = 0.0
//        var totalWeight = 0.0
//        
//        for edge in edges {
//            nodeIds.append(edge.target)
//            totalLength += edge.length
//            totalWeight += edge.weight
//            let coords = edge.coordinates.map { $0.coordinate }
//            if coordinates.isEmpty {
//                coordinates.append(contentsOf: coords)
//            } else {
//                coordinates.append(contentsOf: coords.dropFirst())
//            }
//        }
//        
//        return RouteResult(
//            nodeIds: nodeIds,
//            coordinates: coordinates,
//            totalLength: totalLength,
//            totalWeight: totalWeight,
//            estimatedTime: totalLength / walkingSpeed,
//            label: label
//        )
//    }
    
    /// We only need the shadiest route for navigation right now — kept as its own
    /// method (rather than the old shadiest/fastest/balanced tuple) since
    /// NavigateViewModel isn't exposing a route-type picker.
    func shadiestRoute(from start: String, to end: String) throws -> RouteResult {
        let edges = try dijkstra(from: start, to: end) { $0.weight }
        return buildResult(from: edges, label: "Shadiest (JSON graph)")
    }
}

@MainActor
@Observable
final class NavigateViewModel: NSObject {
    
    var shadedRouteResult: RouteResult?
    var camera: MapCameraPosition = .automatic
    var currentStepIndex: Int = 0
    var distanceToNextStep: CLLocationDistance = 0
    var isNavigating = false
    var errorMessage: String?
    
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
    
    private var maneuvers: [(instruction: String, coordinate: CLLocationCoordinate2D, distanceFromStart: CLLocationDistance)] = []
    private var cumulativeDistances: [CLLocationDistance] = []
    
    
    //Ini yang jalanna normal apple
    /// Instruksi yang benar-benar punya teks (step pertama biasanya kosong)
    //    var activeSteps: [MKRoute.Step] {
    //        route?.steps.filter { !$0.instructions.isEmpty } ?? []
    //    }
    
    /// Estimasi sisa jarak dari instruksi yang sedang aktif sampai tujuan akhir.
    /// Dijumlah dari panjang tiap step yang tersisa — pendekatan sederhana untuk demo,
    /// bukan jarak presisi dari posisi persis user saat ini.
    //    var remainingDistance: CLLocationDistance {
    //        let steps = activeSteps
    //        guard currentStepIndex < steps.count else { return 0 }
    //        return steps[currentStepIndex...].reduce(0) { $0 + $1.distance }
    //    }
    
    /// Estimasi sisa waktu tempuh, dihitung proporsional terhadap sisa jarak
    /// dibanding total jarak & waktu tempuh rute (MKRoute tidak menyediakan estimasi per-step).
    //    var remainingTravelTime: TimeInterval {
    //        guard let route, route.distance > 0 else { return 0 }
    //        let fraction = remainingDistance / route.distance
    //        return route.expectedTravelTime * fraction
    //    }
    //
    //    var estimatedArrivalDate: Date {
    //        Date().addingTimeInterval(remainingTravelTime)
    //    }
    
    //    func startNavigation(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
    //        await calculateRoute(from: origin, to: destination)
    //        if route != nil {
    //            isNavigating = true
    //            startCameraLoop()
    //        }
    //    }
    //
    //    func stopNavigation() {
    //        isNavigating = false
    //        route = nil
    //        currentStepIndex = 0
    //        stopCameraLoop()
    //        displayedCoordinate = nil // biar navigasi berikutnya snap dari posisi baru, bukan interpolasi dari posisi lama
    //        camera = .automatic
    //    }
    
    // Ini yang shaded
    override init() {
        super.init()
        loadGraph()
    }
    
    var activeSteps: [NavigationStep] {
        var result: [NavigationStep] = []
        var previousDistance: CLLocationDistance = 0
        for maneuver in maneuvers {
            let segmentLength = max(maneuver.distanceFromStart - previousDistance, 0)
            result.append(NavigationStep(instructions: maneuver.instruction, distance: segmentLength))
            previousDistance = maneuver.distanceFromStart
        }
        return result
    }
    
    var remainingDistance: CLLocationDistance {
        guard let shadedRouteResult else { return 0 }
        let total = cumulativeDistances.last ?? shadedRouteResult.totalLength
        guard currentStepIndex < maneuvers.count else { return 0 }
        let traveled = maneuvers[currentStepIndex].distanceFromStart
        return max(total - traveled, 0)
    }
    
    var remainingTravelTime: TimeInterval {
        guard let shadedRouteResult, shadedRouteResult.totalLength > 0 else { return 0 }
        let fraction = remainingDistance / shadedRouteResult.totalLength
        return shadedRouteResult.estimatedTime * fraction
    }
    
    var estimatedArrivalDate: Date {
        Date().addingTimeInterval(remainingTravelTime)
    }
    
    private(set) var selectedKind: String = "shaded"
    
    func startNavigation(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, kind: String) async {
        selectedKind = kind
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
    }
    
    
    private func calculateNativeRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
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
                label: "Fastest (Apple Maps)"
            )
            self.shadedRouteResult = result
            self.currentStepIndex = 0
            self.errorMessage = nil
            buildManeuvers(from: result)
        } catch {
            self.errorMessage = "Gagal menghitung rute: \(error.localizedDescription)"
        }
    }
    
    /// Dipanggil setiap ada update lokasi user untuk maju ke instruksi berikutnya
    //    func updateProgress(userLocation: CLLocation) {
    //        let steps = activeSteps
    //        guard currentStepIndex < steps.count else { return }
    //
    //        let step = steps[currentStepIndex]
    //        guard step.polyline.pointCount > 0 else { return }
    //
    //        let stepCoordinate = step.polyline.points()[0].coordinate
    //        let stepLocation = CLLocation(latitude: stepCoordinate.latitude, longitude: stepCoordinate.longitude)
    //        let distance = userLocation.distance(from: stepLocation)
    //        distanceToNextStep = distance
    //
    //        // Kalau sudah dekat (<25m) dengan titik instruksi, lanjut ke step berikutnya
    //        if distance < 25, currentStepIndex < steps.count - 1 {
    //            currentStepIndex += 1
    //        }
    //    }
    
    func calculateRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, kind: String) async {
        if kind == "fastest" {
            await calculateNativeRoute(from: origin, to: destination)
        } else {
            await calculateShadedRoute(from: origin, to: destination)
        }
    }
        
    func calculateShadedRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        guard let graph, let planner else {
            errorMessage = "Route graph (1400.json) failed to load — check it's included in the app bundle."
            return
        }
        
        let startSnap = graph.snap(to: origin)
        let endSnap = graph.snap(to: destination)
        
        guard case .snapped(let sNode, _) = startSnap, case .snapped(let eNode, _) = endSnap else {
            // Only reachable if the graph is empty or somehow degenerate (see snap()'s
            // generous limit) — not a normal "too far away" case anymore.
            errorMessage = "Couldn't find any usable point in the route graph near your start/destination."
            return
        }
        
        async let lead = nativeWalkingLegIfNeeded(from: origin, to: sNode.coordinate)
        async let trail = nativeWalkingLegIfNeeded(from: eNode.coordinate, to: destination)
        let (leadLeg, trailLeg) = await (lead, trail)
        
        do {
            let core = try planner.shadiestRoute(from: sNode.id, to: eNode.id)
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
    
    func updateProgress(userLocation: CLLocation) {
        guard !maneuvers.isEmpty, let shadedRouteResult else { return }
        
        // Find nearest coordinate index along the stitched polyline to know how far along we are.
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
    
    // MARK: - Graph loading
    
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
    
    // MARK: - Approach/trail legs + stitching
    
    private let snapThresholdMeters: CLLocationDistance = 20
    
    private func calculateDistance(a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
    
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
                label: "Approach Leg"
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
            label: core.label
        )
    }
    
    // MARK: - Turn-by-turn derivation
    
    /// The JSON graph doesn't carry instruction text like MKRoute.steps does, so we
    /// derive simple "turn left/right" maneuvers from bearing changes along the
    /// stitched polyline, same approach used in RouteMapView's NavigationSession.
    private func buildManeuvers(from route: RouteResult) {
        cumulativeDistances = [0]
        let coords = route.coordinates
        for i in 1..<max(coords.count, 1) where i < coords.count {
            let d = calculateDistance(a: coords[i - 1], b: coords[i])
            cumulativeDistances.append(cumulativeDistances[i - 1] + d)
        }
        
        maneuvers = []
        guard coords.count > 2 else {
            if let last = coords.last {
                maneuvers = [(instruction: "Arrive at destination", coordinate: last, distanceFromStart: cumulativeDistances.last ?? 0)]
            }
            return
        }
        
        for i in 1..<(coords.count - 1) {
            let b1 = bearing(coords[i - 1], coords[i])
            let b2 = bearing(coords[i], coords[i + 1])
            var delta = b2 - b1
            delta = (delta + 540).truncatingRemainder(dividingBy: 360) - 180
            guard abs(delta) > 25 else { continue }
            let text = delta > 0 ? "Turn right" : "Turn left"
            maneuvers.append((instruction: text, coordinate: coords[i], distanceFromStart: cumulativeDistances[i]))
        }
        maneuvers.append((instruction: "Arrive at destination", coordinate: coords[coords.count - 1], distanceFromStart: cumulativeDistances.last ?? 0))
        
        if maneuvers.isEmpty, let last = coords.last {
            maneuvers = [(instruction: "Continue straight", coordinate: last, distanceFromStart: cumulativeDistances.last ?? 0)]
        }
    }
    
    private func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }
    
    // MARK: - Camera loop
    
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

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
