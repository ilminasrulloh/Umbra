//
//  RoutePlanner.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import Foundation
import MapKit

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
    
    func shadiestRoute(from start: String, to end: String) throws -> RouteResult {
        let edges = try dijkstra(from: start, to: end) { $0.weight }
        return buildResult(from: edges, label: "shaded")
    }
    
    private func buildResult(from edges: [RouteEdge], label: String) -> RouteResult {
        guard let first = edges.first else {
            return RouteResult(nodeIds: [], coordinates: [], totalLength: 0, totalWeight: 0, estimatedTime: 0, label: label, segments: [])
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
            shadedLength: shadedLength,
            segments: [])
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
}
