//
//  RouteOptionsCard.swift
//  Umbra
//
//  Created by Davin P on 06/07/26.
//

import SwiftUI

/// Reusable Component for Route Options
struct RouteOptionCard: View {
    let option: RouteOption
//    var isSelected: Bool = false
//    var onSelect: () -> Void = {}
    var onStart: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let icon = option.leadingIcon {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    Text(option.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Text(option.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(option.durationText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            Spacer(minLength: 8)

            StartButton(action: onStart)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Start route options button
private struct StartButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("Start")
//                    .fontWeight(.semibold)
                Image(systemName: "chevron.forward.2")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Card states") {
    VStack(spacing: 12) {
        ForEach(RouteOption.sample) { option in
            RouteOptionCard(option: option) {
                print("Start tapped: \(option.title)")
            }
        }
    }
    .padding()
    .background(Color(.systemBackground))
}
