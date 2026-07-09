//
//  RouteGraphData.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import Foundation
import MapKit

enum EnvironmentType: String, Codable {
    case sunny
    case shaded
    case indoor
}

struct RouteGraphData: Codable {
    let nodes: [RouteNode]
    let edges: [RouteEdge]
}

struct RouteNode: Codable {
    let id: String
    let lat: Double
    let lon: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
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

struct EdgeCoordinate: Codable {
    let lat: Double
    let lon: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
