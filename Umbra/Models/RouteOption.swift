//
//  RouteOption.swift
//  Umbra
//
//  Created by Davin P on 06/07/26.
//

import SwiftUI

/// attributes for route option
struct RouteOption: Identifiable, Equatable {
    let id = UUID()
    let shadePercent: Int
    let subtitle: String
    let minutes: Int
    let meters: Int
    let isRecommended: Bool

    var title: String {
        "\(shadePercent)% Shaded"
    }

    var durationText: String {
        "\(minutes) mins  •  \(meters) m"
    }

    /// emoji for recommended route
    var leadingIcon: String? {
        isRecommended ? "building.2" : nil
    }
}

extension RouteOption {
    /// sample data for route option (will change for ViewModel later)
    static let sample: [RouteOption] = [
        RouteOption(shadePercent: 45, subtitle: "Recommended", minutes: 7, meters: 700, isRecommended: true),
        RouteOption(shadePercent: 52, subtitle: "Takes a bit longer, but totally sweat-free", minutes: 10, meters: 950, isRecommended: false),
        RouteOption(shadePercent: 23, subtitle: "Expect some direct sunlight", minutes: 5, meters: 450, isRecommended: false)
    ]
}
