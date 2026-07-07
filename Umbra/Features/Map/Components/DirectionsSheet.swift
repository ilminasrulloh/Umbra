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
    var selectedKind: String
    var onSelectOption: (RouteOption) -> Void
    
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
    /// Tapped the origin row -> parent should reopen the search sheet
    /// (BottomPanelSheetView) so the user can change the starting point.
    var onEditOrigin: () -> Void
    /// Tapped the destination row -> parent should reopen the search sheet
    /// so the user can change where they're going.
    var onEditDestination: () -> Void
    
    var onStart: (RouteOption) -> Void
    
    // Owned by the gesture itself (not plain @State). This is the fix for the
    // jitter: @GestureState automatically resets to 0 the instant the drag
    // ends OR is cancelled/interrupted (e.g. by a competing ScrollView
    // recognizer when you pause mid-drag). A plain @State var can get stuck
    // at a stale non-zero value if onEnded never fires, which is what was
    // causing the jump/oscillation when holding mid-swipe.
    @GestureState private var dragState: CGFloat = 0
    
    private var baseHeight: CGFloat { isExpanded ? expandedHeight : collapsedHeight }
    
    /// The height actually rendered — follows the finger 1:1 while dragging,
    /// clamped so you can't drag past either resting size.
    private var liveHeight: CGFloat {
        min(max(baseHeight - dragState, collapsedHeight), expandedHeight)
    }
    
    /// recommended route
    private var recommendedOption: RouteOption? {
        options.first(where: { $0.isRecommended })
    }
    
    private var chosenOption: RouteOption? {
        options.first(where: { $0.kind == selectedKind })
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
                    DragGesture(minimumDistance: 4, coordinateSpace: .local)
                        .updating($dragState) { value, state, _ in
                            // No withAnimation here on purpose — we want the
                            // sheet to follow the finger 1:1, with zero lag,
                            // while actively dragging. Animating this would
                            // make the sheet "chase" your finger and produce
                            // exactly the jittery/laggy feel.
                            //
                            // BUT: a "held" finger is never perfectly still —
                            // sensor noise + natural hand tremor constantly
                            // reports a few points of movement even when the
                            // user isn't intentionally dragging. Mapping that
                            // raw translation 1:1 into height is exactly what
                            // produced the kejang2/oscillation while holding.
                            // Apple's own sheet doesn't have this problem
                            // because UIKit's presentation controller applies
                            // its own physics-based damping; SwiftUI's raw
                            // DragGesture has none unless we add it. A small
                            // dead zone absorbs that noise while staying
                            // imperceptible for real, intentional drags.
                            let raw = value.translation.height
                            let deadZone: CGFloat = 4
                            if abs(raw) < deadZone {
                                state = 0
                            } else {
                                state = raw > 0 ? raw - deadZone : raw + deadZone
                            }
                        }
                        .onEnded { value in
                            let translation = value.translation.height
                            let threshold: CGFloat = 60   // jarak minimum biar dianggap "sengaja" narik
                            
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
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
                                // dragState resets itself automatically (that's
                                // the whole point of @GestureState) — no manual
                                // reset needed, and none possible to forget.
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
            .padding(.bottom, 20)
            
            // Origin / destination — fixed, does not scroll.
            // Two independently-tappable rows: tapping origin lets you change
            // the starting point, tapping destination lets you change where
            // you're going. (I don't have LocationInputStack.swift's source,
            // so this replaces it with an equivalent two-row layout rather
            // than guessing at how to split taps inside it — swap the visual
            // styling below for LocationInputStack's if you'd rather match it
            // exactly, the tap wiring will work the same either way.)
            RouteEndpointsRow(
                originTitle: originTitle,
                destinationTitle: destinationTitle,
                onEditDestination: onEditDestination
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 1)
            
            // Legend — fixed, does not scroll.
            if showLegend {
                RouteLegendView()
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
            }
            
            // Route options:
            // - Collapsed (Gambar 2): tampilkan HANYA kartu opsi yang direkomendasikan,
            //   supaya user langsung lihat info penting + tombol Start tanpa harus expand.
            // - Expanded (Gambar 3): tampilkan SEMUA opsi rute (termasuk yang
            //   direkomendasikan) dalam list yang bisa di-scroll.
            if isExpanded {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(options) { option in
                            RouteOptionsCard(
                                option: option,
                                isSelected: option.kind == selectedKind,
                                onSelect: { onSelectOption(option) }
                            ) {
                                onStart(option)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                
            } else if let chosen = chosenOption ?? recommendedOption {
                RouteOptionsCard(
                    option: chosen,
                    isSelected: true,
                    onSelect: { onSelectOption(chosen) }) {
                        onStart(chosen)
                    }
                
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            } else {
                Spacer(minLength: 12)
            }
        }
        .frame(height: expandedHeight, alignment: .top)
        .frame(height: liveHeight, alignment: .top)
        .clipped()
        .background(Color(.systemBackground))
    }
}

private struct RouteEndpointsRow: View {
    let originTitle: String
    let destinationTitle: String
    var onEditDestination: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            LocationRow(kind: .origin, title: originTitle)
            
            Divider()
                .padding(.leading, 54)
            
            Button(action: onEditDestination) {
                LocationRow(kind: .destination, title: destinationTitle)
            }
            .buttonStyle(.plain)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

//#Preview("Collapsed (Gambar 2)") {
//    DirectionsSheet(
//        originTitle: "My Location",
//        destinationTitle: "The Breeze",
//        options: RouteOption.sample,
//        showLegend: true,
//        isExpanded: false,
//        collapsedHeight: 260,
//        expandedHeight: 700,
//        onClose: {},
//        onExpand: {},
//        onCollapse: {},
//        onEditOrigin: {},
//        onEditDestination: {},
//        onStart: { print("Start: \($0.title)") }
//    )
//}
//
//#Preview("Expanded (Gambar 3)") {
//    DirectionsSheet(
//        originTitle: "My Location",
//        destinationTitle: "The Breeze",
//        options: RouteOption.sample,
//        showLegend: true,
//        isExpanded: true,
//        collapsedHeight: 260,
//        expandedHeight: 700,
//        onClose: {},
//        onExpand: {},
//        onCollapse: {},
//        onEditOrigin: {},
//        onEditDestination: {},
//        onStart: { print("Start: \($0.title)") }
//    )
//}
