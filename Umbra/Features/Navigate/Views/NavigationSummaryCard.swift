//
//  NavigationSummaryCard.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 06/07/26.
//

import SwiftUI

struct NavigationSummaryCard: View {
    let etaMinutesText: String
    let arrivalTimeText: String
    let remainingDistanceText: String
    let onEndRoute: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(etaMinutesText)
                        .font(.system(size: 28, weight: .bold))
                    Text("mins")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("\(arrivalTimeText) • \(remainingDistanceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(action: onEndRoute) {
                Text("End Route")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color.red, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.15), radius: 10, y: -2)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
