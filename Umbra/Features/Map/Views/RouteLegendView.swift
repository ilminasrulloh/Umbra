//
//  RouteLegendView.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI

// MARK: - Legend ("Exposed" / "Shaded")
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

