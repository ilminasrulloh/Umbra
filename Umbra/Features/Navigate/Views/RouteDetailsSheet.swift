//
//  RouteDetailsSheet.swift
//  Umbra
//
//  Created by Davin P on 09/07/26.
//

import SwiftUI
import CoreLocation

struct RouteDetailsSheet: View {
    let startAddress: String
    let destinationAddress: String
    let steps: [NavigationStep]
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    endpointRow(
                        icon: "building.2.fill",
                        iconBackground: Color(.systemGray4),
                        title: "Start",
                        subtitle: startAddress
                    )

                    Divider().padding(.leading, 68)

                    proceedRow

                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        Divider().padding(.leading, 54)
                        instructionRow(for: step)
                    }

                    Divider().padding(.leading, 68)

                    endpointRow(
                        icon: "bag.fill",
                        iconBackground: .orange,
                        title: "Arrive",
                        subtitle: destinationAddress
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color(.systemGray2), in: Circle())
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func endpointRow(icon: String, iconBackground: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }

    /// Baris pembuka sebelum instruksi pertama — jarak dari lokasi asli user
    /// ke titik mulai rute sengaja tidak ditampilkan angkanya, cukup label saja,
    /// sama seperti referensi desainnya.
    private var proceedRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray3), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(width: 36)

            Text("Proceed to the route")
                .font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private func instructionRow(for step: NavigationStep) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName(for: step.instructions))
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(distanceText(for: step.distance))
                    .font(.system(size: 16, weight: .bold))
                Text(step.instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Formatting

    private func distanceText(for meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }

    private func iconName(for instructions: String) -> String {
        let text = instructions.lowercased()
        if text.contains("left") || text.contains("kiri") {
            return "arrow.turn.up.left"
        } else if text.contains("right") || text.contains("kanan") {
            return "arrow.turn.up.right"
        } else if text.contains("u-turn") || text.contains("putar balik") {
            return "arrow.uturn.left"
        } else if text.contains("roundabout") || text.contains("bundaran") {
            return "arrow.triangle.2.circlepath"
        } else if text.contains("stairs") || text.contains("tangga") {
            return "figure.stairs"
        } else if text.contains("merge") || text.contains("gabung") {
            return "arrow.triangle.merge"
        } else if text.contains("destination") || text.contains("tujuan") || text.contains("arrive") {
            return "flag.checkered"
        } else {
            return "arrow.up"
        }
    }
}
