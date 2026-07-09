//
//  RouteManager.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import Foundation

class RouteManager {
    var graph: RouteGraph?
    var planner: RoutePlanner?

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
}
