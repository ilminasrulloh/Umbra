//
//  LocationRowView.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI

// MARK: - Location row (origin / destination)

struct LocationRow: View {
    enum Kind {
        case origin
        case destination

        var iconName: String {
            switch self {
            case .origin: return "location.fill"
            case .destination: return "bag.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .origin: return .blue
            case .destination: return .orange
            }
        }
    }

    let kind: Kind
    let title: String
    /// Kalau false, ikon "bisa diedit" (garis 3) di kanan disembunyikan —
    /// supaya baris yang memang tidak bisa di-tap tidak terlihat seperti bisa di-tap.
    var isInteractive: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(kind.iconColor)
                    .frame(width: 28, height: 28)
                Image(systemName: kind.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.primary)

            Spacer()

            if isInteractive {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}
