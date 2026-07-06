//
//  DirectionsSheet.swift
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
    
    /// true = Gambar 3 (full route list), false = Gambar 2 (just origin/destination)
    var isExpanded: Bool
    
    /// Heights for the two resting states. Pass expandedHeight computed from
    /// screen size (e.g. geo.size.height * 0.92) so it's near-full-screen.
    var collapsedHeight: CGFloat
    var expandedHeight: CGFloat
    
    /// X button tapped, or dragged down while already collapsed.
    var onClose: () -> Void
    /// Dragged up past the midpoint while collapsed -> parent switches to expanded.
    var onExpand: () -> Void
    /// Dragged down past the midpoint while expanded -> parent switches to collapsed.
    var onCollapse: () -> Void
    
    var onStart: (RouteOption) -> Void
    
    // Tracks the live drag distance; automatically resets to 0 when the
    // gesture ends, which is what lets the final settle animate smoothly.
    @State private var dragTranslation: CGFloat = 0
    
    private var baseHeight: CGFloat { isExpanded ? expandedHeight : collapsedHeight }
    
    /// The height actually rendered — follows the finger 1:1 while dragging,
    /// clamped so you can't drag past either resting size.
    private var liveHeight: CGFloat {
        min(max(baseHeight - dragTranslation, collapsedHeight), expandedHeight)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle — swipe down to close/collapse, swipe up to expand.
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .contentShape(Rectangle().inset(by: -12)) // bigger hit area
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragTranslation = value.translation.height
                        }
                        .onEnded { value in
                            let translation = value.translation.height
                            let threshold: CGFloat = 60   // jarak minimum biar dianggap "sengaja" narik
                            
                            if translation < -threshold {
                                // Narik ke ATAS cukup jauh -> expand (kalau belum expanded)
                                if !isExpanded {
                                    onExpand()
                                }
                                // kalau udah expanded, gak ngapa-ngapain (tetep expanded)
                            } else if translation > threshold {
                                // Narik ke BAWAH cukup jauh
                                if isExpanded {
                                    onCollapse()
                                } else {
                                    onClose()
                                }
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                dragTranslation = 0
                            }
                        }
                )
            
            // Header — fixed, does not scroll.
            HStack {
                Text("Directions")
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(10)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // Origin / destination — fixed, does not scroll.
            LocationInputStack(originTitle: originTitle, destinationTitle: destinationTitle)
                .padding(.horizontal, 20)
            
            // Legend — fixed, does not scroll.
            if showLegend {
                RouteLegendView()
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
            }
            
            // Route options — ONLY this part scrolls, and only shows once expanded.
            if isExpanded {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(options) { option in
                            RouteOptionCard(option: option) {
                                onStart(option)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            } else {
                Spacer(minLength: 12)
            }
        }
        .frame(height: liveHeight)
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

#Preview("Collapsed (Gambar 2)") {
    DirectionsSheet(
        originTitle: "My Location",
        destinationTitle: "The Breeze",
        options: RouteOption.sample,
        showLegend: true,
        isExpanded: false,
        collapsedHeight: 260,
        expandedHeight: 700,
        onClose: {},
        onExpand: {},
        onCollapse: {},
        onStart: { print("Start: \($0.title)") }
    )
}

#Preview("Expanded (Gambar 3)") {
    DirectionsSheet(
        originTitle: "My Location",
        destinationTitle: "The Breeze",
        options: RouteOption.sample,
        showLegend: true,
        isExpanded: true,
        collapsedHeight: 260,
        expandedHeight: 700,
        onClose: {},
        onExpand: {},
        onCollapse: {},
        onStart: { print("Start: \($0.title)") }
    )
}
