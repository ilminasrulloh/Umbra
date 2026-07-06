//
//  DirectionSheet.swift
//  Umbra
//
//  Created by Davin P on 06/07/26.
//

import SwiftUI

struct DirectionsSheet: View {
    let originTitle: String
    let destinationTitle: String
    let options: [RouteOption]
    var showLegend: Bool = false
    var onClose: () -> Void
    var onStart: (RouteOption) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            // Header
            HStack {
                Text("Directions")
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.black)
                        .padding(10)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .padding(.top, )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Origin / destination
            LocationInputStack(originTitle: originTitle, destinationTitle: destinationTitle)
                .padding(.horizontal, 20)

            if showLegend {
                RouteLegendView()
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }

            // Route options
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(options) { option in
                        RouteOptionCard(option: option) {
                            onStart(option)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color(.systemBackground))
    }
}

/// The "Exposed / Shaded" legend shown on the map screen variant.
struct RouteLegendView: View {
    var body: some View {
        HStack(spacing: 24) {
            legendItem(color: .yellow, label: "Exposed")
            legendItem(color: .blue, label: "Shaded")
            Spacer()
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(color)
                .frame(width: 22, height: 4)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Directions Sheet") {
    DirectionsSheet(
        originTitle: "My Location",
        destinationTitle: "The Breeze",
        options: RouteOption.sample,
        showLegend: true,
        onClose: {},
        onStart: { print("Start: \($0.title)") }
    )
}
