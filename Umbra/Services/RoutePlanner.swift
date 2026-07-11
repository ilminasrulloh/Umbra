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

    /// Kalau rute alternatif berbagi lebih dari sekian % PANJANG JALUR dengan rute
    /// yang sudah diterima, dianggap "itu-itu juga" — bukan alternatif yang worth ditampilkan.
    private let maxSharedLengthRatio: Double = 0.6

    /// Kalau rute alternatif jaraknya lebih dari sekian kali lipat rute utama,
    /// dianggap kelewat memutar / kurang akurat buat direkomendasikan sebagai "shaded route".
    private let maxDetourRatio: Double = 1.5

    /// Pengali penalty ke edge yang sudah dipakai rute sebelumnya, biar Dijkstra
    /// dipaksa cari jalur yang BEDA (bukan cuma variasi tipis dari rute #1).
    private let reroutePenaltyMultiplier: Double = 8.0

    init(graph: RouteGraph, walkingSpeed: Double = 1.4) {
        self.graph = graph
        self.walkingSpeed = walkingSpeed
    }

    /// Dipertahankan untuk tempat lain yang cuma butuh SATU rute paling teduh.
    func shadiestRoute(from start: String, to end: String) throws -> RouteResult {
        let edges = try dijkstra(from: start, to: end) { $0.weight }
        return buildResult(from: edges, label: "shaded")
    }

    /// Sampai `maxRoutes` rute teduh yang BERBEDA jalurnya, diurutkan dari paling teduh.
    /// Kalau cuma ada 1 jalur masuk akal (yang lain terlalu mirip/memutar), yang
    /// dikembalikan cuma 1 elemen — itu memang perilaku yang diinginkan.
    func shadiestRoutes(from start: String, to end: String, maxRoutes: Int = 2) throws -> [RouteResult] {
        let primary = try dijkstra(from: start, to: end) { $0.weight }
        guard maxRoutes > 1, !primary.isEmpty else {
            return [buildResult(from: primary, label: "shaded")]
        }

        var acceptedPaths: [[RouteEdge]] = [primary]
        let primaryLength = totalLength(of: primary)
        var penalizedKeys: Set<String> = Set(primary.map(edgeKey))

        while acceptedPaths.count < maxRoutes {
            guard let candidate = try? dijkstra(from: start, to: end, cost: { edge in
                penalizedKeys.contains(edgeKey(edge)) ? edge.weight * reroutePenaltyMultiplier : edge.weight
            }), !candidate.isEmpty else { break }

            // Keakuratan: rute alternatif nggak boleh jauh lebih panjang dari rute utama.
            guard totalLength(of: candidate) <= primaryLength * maxDetourRatio else { break }

            // Jangan dobel: rute baru harus cukup beda dari SEMUA rute yang sudah diterima.
            guard acceptedPaths.allSatisfy({ sharedLengthRatio(candidate, $0) <= maxSharedLengthRatio }) else { break }

            acceptedPaths.append(candidate)
            penalizedKeys.formUnion(candidate.map(edgeKey))
        }

        return acceptedPaths.map { buildResult(from: $0, label: "shaded") }
    }

    private func edgeKey(_ edge: RouteEdge) -> String { "\(edge.source)->\(edge.target)" }

    private func totalLength(of edges: [RouteEdge]) -> Double {
        edges.reduce(0) { $0 + $1.length }
    }

    private func sharedLengthRatio(_ candidate: [RouteEdge], _ other: [RouteEdge]) -> Double {
        let otherKeys = Set(other.map(edgeKey))
        let sharedLength = candidate
            .filter { otherKeys.contains(edgeKey($0)) }
            .reduce(0) { $0 + $1.length }
        let candidateLength = totalLength(of: candidate)
        guard candidateLength > 0 else { return 0 }
        return sharedLength / candidateLength
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

            let coords = edge.coordinates.map { $0.coordinate }

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
            estimatedTime: totalLength / walkingSpeed,
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
