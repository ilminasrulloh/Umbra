//
//  RouteResult.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI
import MapKit

struct RouteResult {
    let nodeIds: [String]
    let coordinates: [CLLocationCoordinate2D]
    let totalLength: Double
    let totalWeight: Double
    let estimatedTime: TimeInterval
    let label: String
    var shadedLength: Double = 0
    var segments: [RouteSegment]
    
    var totalLengthKm: Double { totalLength / 1000 }
    var estimatedTimeMinutes: Double { estimatedTime / 60 }
    
    var shadePercent: Int {
        guard totalLength > 0 else { return 0 }
        return Int((shadedLength/totalLength) * 100)
    }
}

struct RouteSegment: Identifiable {
    let id = UUID()
    var coordinate: [CLLocationCoordinate2D]
    var environment: String
    
    var color: Color {
        switch environment {
        case "sunny": return .yellow
        case "indoor": return .green
        case "shaded": return .blue
        default: return .gray
        }
    }
}
