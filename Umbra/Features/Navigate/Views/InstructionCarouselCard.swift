//
//  InstructionCarouselCard.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 06/07/26.
//

import SwiftUI
import MapKit

struct InstructionCarouselCard: View {
    let steps: [NavigationStep]
    @Binding var selectedIndex: Int

    /// Index step yang SEDANG aktif secara nyata (bukan yang lagi di-preview lewat swipe)
    let activeStepIndex: Int
    /// Jarak live (real-time, dari GPS) ke step yang sedang aktif
    let liveDistanceToActiveStep: CLLocationDistance
    /// Dipanggil ketika card di-tap — dipakai untuk membuka modal detail rute.
    var onTap: () -> Void = {}

    private var selectedStep: NavigationStep? {
        steps.indices.contains(selectedIndex) ? steps[selectedIndex] : nil
    }

    private var cardHeight: CGFloat {
        selectedStep?.entranceImageName != nil ? 220 : 92
    }

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $selectedIndex) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    InstructionCardContent(
                        step: step,
                        distanceText: distanceText(for: index, step: step)
                    )
                    .tag(index)
                    .padding(.horizontal, 20)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: cardHeight)
            .animation(.easeInOut(duration: 0.2), value: cardHeight)

            if steps.count > 1 {
                PageDots(count: steps.count, currentIndex: selectedIndex)
            }
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }


    /// Untuk step yang sedang aktif, pakai jarak live dari GPS.
    /// Untuk step lain (yang lagi di-preview), pakai panjang segmen step itu sendiri.
    private func distanceText(for index: Int, step: NavigationStep) -> String {
        let meters = index == activeStepIndex ? liveDistanceToActiveStep : step.distance
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
}

private struct InstructionCardContent: View {
    let step: NavigationStep
    let distanceText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: iconName(for: step.instructions))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(distanceText)
                        .font(.system(size: 24, weight: .bold))
                    Text(step.instructions)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let entranceImageName = step.entranceImageName {
                Image(entranceImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 108)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    /// Tebak ikon panah berdasarkan kata kunci di teks instruksi.
    /// MapKit tidak punya enum tipe belokan eksplisit, jadi ini pendekatan heuristik sederhana.
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
        } else if text.contains("merge") || text.contains("gabung") {
            return "arrow.triangle.merge"
        } else if text.contains("destination") || text.contains("tujuan") || text.contains("arrive") {
            return "flag.checkered"
        } else {
            return "arrow.up"
        }
    }
}

/// Page control ala HIG (mirip `UIPageControl`): maksimal `maxVisible` dot yang tampak
/// sekaligus, mengikuti dot yang aktif. Kalau ada dot tersembunyi di salah satu ujung,
/// dot paling ujung yang terlihat mengecil bertahap sebagai sinyal "masih ada lagi" —
/// persis perilaku bawaan `UIPageControl` saat jumlah halaman melebihi kapasitas tampilan.
private struct PageDots: View {
    let count: Int
    let currentIndex: Int

    private let maxVisible = 7
    private let baseDotSize: CGFloat = 6

    /// Rentang index yang benar-benar dirender, mengikuti currentIndex tapi tetap
    /// di dalam batas [0, count).
    private var visibleRange: Range<Int> {
        guard count > maxVisible else { return 0..<count }
        let half = maxVisible / 2
        let start = min(max(currentIndex - half, 0), count - maxVisible)
        return start..<(start + maxVisible)
    }

    /// Skala dot berdasarkan seberapa dekat dengan ujung window yang sedang tampil —
    /// dot di posisi paling luar mengecil paling banyak, tetangganya sedikit lebih kecil,
    /// dot di tengah ukuran penuh. Hanya berlaku kalau memang ada dot yang tersembunyi
    /// di sisi tersebut (bukan ujung asli dari keseluruhan step).
    private func scale(for index: Int) -> CGFloat {
        guard count > maxVisible else { return 1.0 }
        let range = visibleRange
        guard let position = range.firstIndex(of: index) else { return 1.0 }
        let offsetFromStart = position - range.lowerBound
        let offsetFromEnd = (range.upperBound - 1) - position

        let hiddenBefore = range.lowerBound > 0
        let hiddenAfter = range.upperBound < count

        if hiddenBefore && offsetFromStart == 0 { return 0.4 }
        if hiddenBefore && offsetFromStart == 1 { return 0.7 }
        if hiddenAfter && offsetFromEnd == 0 { return 0.4 }
        if hiddenAfter && offsetFromEnd == 1 { return 0.7 }
        return 1.0
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(visibleRange, id: \.self) { index in
                let size = baseDotSize * scale(for: index)
                Circle()
                    .fill(index == currentIndex ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: size, height: size)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentIndex)
    }
}

// MARK: - Preview

/// Data dummy buat ngecek tampilan carousel di Canvas — termasuk step "Enter the
/// Building" yang bakal nampilin foto entrance dummy ("entranceDummy" di Assets.xcassets).
#Preview("Foto Entrance") {
    struct PreviewHost: View {
        @State private var index = 1
        let steps = [
            NavigationStep(instructions: "Walk toward the building", distance: 45, coordinate: .init(latitude: 0, longitude: 0)),
            NavigationStep(instructions: "Enter the Building", distance: 12, coordinate: .init(latitude: 0, longitude: 0), entranceImageName: "entranceDummy"),
            NavigationStep(instructions: "Take lift to 3", distance: 0, coordinate: .init(latitude: 0, longitude: 0)),
            NavigationStep(instructions: "Turn Right", distance: 20, coordinate: .init(latitude: 0, longitude: 0)),
            NavigationStep(instructions: "Arrive at destination", distance: 5, coordinate: .init(latitude: 0, longitude: 0))
        ]

        var body: some View {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                InstructionCarouselCard(
                    steps: steps,
                    selectedIndex: $index,
                    activeStepIndex: index,
                    liveDistanceToActiveStep: steps[index].distance,
                    onTap: { print("tapped -> buka RouteDetailsSheet") }
                )
            }
        }
    }
    return PreviewHost()
}

/// Ngecek kondisi page dots kalau step-nya banyak (>7) — dot di ujung window harus mengecil.
#Preview("Page dots banyak step") {
    struct PreviewHost: View {
        @State private var index = 5
        let steps = (0..<15).map { i in
            NavigationStep(instructions: "Step \(i)", distance: Double(i * 10), coordinate: .init(latitude: 0, longitude: 0))
        }

        var body: some View {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                InstructionCarouselCard(
                    steps: steps,
                    selectedIndex: $index,
                    activeStepIndex: index,
                    liveDistanceToActiveStep: steps[index].distance
                )
            }
        }
    }
    return PreviewHost()
}
