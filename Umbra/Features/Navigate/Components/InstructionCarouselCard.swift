//
//  InstructionCarouselCard.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 06/07/26.
//

import SwiftUI
import MapKit

struct InstructionCarouselCard: View {
//    let steps: [MKRoute.Step]
    let steps: [NavigationStep]
    @Binding var selectedIndex: Int

    /// Index step yang SEDANG aktif secara nyata (bukan yang lagi di-preview lewat swipe)
    let activeStepIndex: Int
    /// Jarak live (real-time, dari GPS) ke step yang sedang aktif
    let liveDistanceToActiveStep: CLLocationDistance

//    var body: some View {
//        VStack(spacing: 10) {
//            TabView(selection: $selectedIndex) {
//                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
//                    InstructionCardContent(
//                        step: step,
//                        distanceText: distanceText(for: index, step: step)
//                    )
//                    .tag(index)
//                    .padding(.horizontal, 20)
//                }
//            }
//            .tabViewStyle(.page(indexDisplayMode: .never))
//            .frame(height: 92)
//
//            if steps.count > 1 {
//                PageDots(count: steps.count, currentIndex: selectedIndex)
//            }
//        }
//        .padding(.vertical, 14)
//        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22))
//        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
//        .padding(.horizontal)
//    }
    
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
            .frame(height: 92)

            if steps.count > 1 {
                PageDots(count: steps.count, currentIndex: selectedIndex)
            }
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal)
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
//    let step: MKRoute.Step
    let step: NavigationStep
    let distanceText: String

    var body: some View {
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

private struct PageDots: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

//#Preview {
//    InstructionCarouselCard(steps: <#[MKRoute.Step]#>, selectedIndex: <#Binding<Int>#>, activeStepIndex: <#Int#>, liveDistanceToActiveStep: <#CLLocationDistance#>)
//}
