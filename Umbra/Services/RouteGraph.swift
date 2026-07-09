//
//  RouteGraph.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import Foundation
import MapKit

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
