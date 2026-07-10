//
//  RouteManager.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import Foundation
import MapKit

class RouteManager {
    var graph: RouteGraph?
    var planner: RoutePlanner?
    var shadedRouteResult: RouteResult?
    var nativeRouteResult: RouteResult?
    var currentStepIndex = 0
    
    private let snapThresholdMeters: CLLocationDistance = 20
    private var cumulativeDistances: [CLLocationDistance] = []
    private var maneuvers: [
        (instruction: String,
         coordinate: CLLocationCoordinate2D,
         distanceFromStart: CLLocationDistance,
         nodeId: String?)
    ] = []

    func loadRouteGraph() {
        guard let url = Bundle.main.url(forResource: "1400", withExtension: "json") else {
            
            return
        }
        do {
            let loadedGraph = try RouteGraph(jsonURL: url)
            self.graph = loadedGraph
            self.planner = RoutePlanner(graph: loadedGraph)
        } catch {
            
        }
    }
    
    func calculateRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, kind: String) async {
        if kind == "fastest" {
            await calculateNativeRoute(from: origin, to: destination)
        } else {
            await calculateShadedRoute(from: origin, to: destination)
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
            shadedRouteResult = result
            currentStepIndex = 0
//            buildManeuvers(from: result)
        } catch {
            
        }
    }
    
    func calculateShadedRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        guard let graph, let planner else { return }
        
        let startSnap = graph.snap(to: origin)
        let endSnap = graph.snap(to: destination)
        
        guard case .snapped(let sNode, _) = startSnap, case .snapped(let eNode, _) = endSnap else {
            return
        }
        
        async let lead = shadedAndNativeRoute(from: origin, to: sNode.coordinate)
        async let trail = shadedAndNativeRoute(from: eNode.coordinate, to: destination)
        let (leadLeg, trailLeg) = await (lead, trail)
        
        do {
            let core = try planner.shadiestRoute(from: sNode.id, to: eNode.id)
            let finalRoute = stitch(lead: leadLeg, core: core, trail: trailLeg)
            
            shadedRouteResult = finalRoute
            currentStepIndex = 0
//            buildManeuvers(from: finalRoute)
        } catch {
            
        }
    }
    
    func shadedAndNativeRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> RouteResult? {
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
    
    func stitch(lead: RouteResult?, core: RouteResult, trail: RouteResult?) -> RouteResult {
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
    
    private func calculateDistance(a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
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
}
