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
    private let snapThresholdMeters: CLLocationDistance = 20
    
    init() {
        loadRouteGraph()
    }
    
    func loadRouteGraph() {
        let filename = getCurrentFilename()
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else { return }
        do {
            let loadedGraph = try RouteGraph(jsonURL: url)
            self.graph = loadedGraph
            self.planner = RoutePlanner(graph: loadedGraph)
        } catch { }
    }
    
    func calculateWalkingRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> [MKRoute] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        request.requestsAlternateRoutes = true
        
        do {
            let response = try await MKDirections(request: request).calculate()
            return response.routes
        } catch {
            return []
        }
    }
    
    func nativeRouteResult(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, label: String = "Fastest (Apple Maps)"
    ) async -> RouteResult? {
        guard let route = await calculateWalkingRoute(from: origin, to: destination).first else { return nil } // ini buat yg di NavigateViewModel
        return RouteResult(
            nodeIds: [],
            coordinates: route.polyline.coordinates,
            totalLength: route.distance,
            totalWeight: 0,
            estimatedTime: route.expectedTravelTime,
            label: label,
            segments: []
        )
    }
    
    func calculateShadedRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, maxRoutes: Int) async -> [RouteResult] {
        let maxGraphDistance: CLLocationDistance = 10000
        let maxSnapDistance: CLLocationDistance = 3000
        
        if calculateDistance(a: origin, b: destination) > maxGraphDistance {
            guard let result = await nativeRouteResult(from: origin, to: destination) else { return [] }
            return [result]
        }
        
        guard let graph, let planner else {
            guard let result = await nativeRouteResult(from: origin, to: destination) else { return [] }
            return [result]
        }
        
        let startSnap = graph.snap(to: origin)
        let endSnap = graph.snap(to: destination)
        
        guard case .snapped(let sNode, _) = startSnap,
              case .snapped(let eNode, _) = endSnap else {
            guard let result = await nativeRouteResult(from: origin, to: destination) else { return [] }
            return [result]
        }
        
        guard calculateDistance(a: origin, b: sNode.coordinate) <= maxSnapDistance, calculateDistance(a: destination, b: eNode.coordinate) <= maxSnapDistance else {
            guard let result = await nativeRouteResult(from: origin, to: destination) else { return [] }
            return [result]
        }
        
        async let lead = nativeWalkingLeg(from: origin, to: sNode.coordinate)
        async let trail = nativeWalkingLeg(from: eNode.coordinate, to: destination)
        let (leadLeg, trailLeg) = await (lead, trail)
        
        do {
            let cores = try planner.shadiestRoutes(from: sNode.id, to: eNode.id, maxRoutes: maxRoutes)
            guard !cores.isEmpty else {
                guard let result = await nativeRouteResult(from: origin, to: destination) else { return [] }
                return [result]
            }
            return cores.map { stitch(lead: leadLeg, core: $0, trail: trailLeg) }
        } catch {
            guard let result = await nativeRouteResult(from: origin, to: destination) else { return [] }
            return [result]
        }
    }
    
    private func nativeWalkingLeg(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> RouteResult? {
        guard calculateDistance(a: from, b: to) > snapThresholdMeters else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            return RouteResult(
                nodeIds: [], coordinates: route.polyline.coordinates,
                totalLength: route.distance, totalWeight: 0,
                estimatedTime: route.expectedTravelTime,
                label: "Approach Leg", segments: []
            )
        } catch {
            return nil
        }
    }
    
    private func calculateDistance(a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
    
    private func stitch(lead: RouteResult?, core: RouteResult, trail: RouteResult?) -> RouteResult {
        var allSegments: [RouteSegment] = []
        var flatCoords: [CLLocationCoordinate2D] = []
        
        if let leadLeg = lead, !leadLeg.coordinates.isEmpty {
            allSegments.append(RouteSegment(coordinate: leadLeg.coordinates, environment: "sunny"))
            flatCoords += leadLeg.coordinates
        }
        if !core.segments.isEmpty {
            allSegments += core.segments
            flatCoords += core.coordinates
        } else {
            allSegments.append(RouteSegment(coordinate: core.coordinates, environment: core.label))
            flatCoords += core.coordinates
        }
        if let trailLeg = trail, !trailLeg.coordinates.isEmpty {
            allSegments.append(RouteSegment(coordinate: trailLeg.coordinates, environment: "sunny"))
            flatCoords += trailLeg.coordinates
        }
        
        return RouteResult(
            nodeIds: core.nodeIds,
            coordinates: flatCoords,
            totalLength: (lead?.totalLength ?? 0) + core.totalLength + (trail?.totalLength ?? 0),
            totalWeight: core.totalWeight,
            estimatedTime: (lead?.estimatedTime ?? 0) + core.estimatedTime + (trail?.estimatedTime ?? 0),
            label: core.label,
            shadedLength: core.shadedLength,
            segments: allSegments
        )
    }
    
    private func getCurrentFilename() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        guard (6...18).contains(hour) else { return "1400" }
        return String(format: "%02d00", hour)
    }
}
