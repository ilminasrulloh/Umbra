//
//  DirectionsSheet.swift
//  Umbra
//
//  Created by Davin P on 06/07/26.
//

import SwiftUI

// MARK: - DirectionsSheet

struct DirectionsSheet: View {
    let originTitle: String
    let destinationTitle: String
    var selectedKind: String

    let options: [RouteOption]
    var onSelectOption: (RouteOption) -> Void

    var showLegend: Bool = false
    var isExpanded: Bool

    var collapsedHeight: CGFloat
    var expandedHeight: CGFloat

    /// X button tapped -> sheet ditutup total (hilang, bukan sekadar minimize).
    var onClose: () -> Void

    /// Drag ke atas cukup jauh (atau flick cepat ke atas) saat collapsed -> parent pindah ke expanded.
    var onExpand: () -> Void

    /// Drag ke bawah cukup jauh (atau flick cepat ke bawah) saat expanded -> parent pindah ke collapsed.
    var onCollapse: () -> Void

    /// Baris origin di-tap -> parent buka lagi search sheet untuk ganti titik awal.
    var onEditOrigin: () -> Void

    /// Baris destination di-tap -> parent buka lagi search sheet untuk ganti tujuan.
    var onEditDestination: () -> Void

    var onStart: (RouteOption) -> Void

    @State private var dragTranslation: CGFloat = 0

    /// Saat true, sheet tidak hilang total -> peta/rute di baliknya tetap kelihatan,
    @State private var isMinimized: Bool = false

    /// Tinggi sheet saat dalam mode minimized (bar kecil, bukan 0/hilang).
    private let minimizedHeight: CGFloat = 85

    private var baseHeight: CGFloat {
        if isMinimized { return minimizedHeight }
        return isExpanded ? expandedHeight : collapsedHeight
    }

    private var travelRange: CGFloat { expandedHeight - collapsedHeight }

    private var liveHeight: CGFloat {
        let proposed = baseHeight - dragTranslation
        if proposed > expandedHeight {
            return expandedHeight + rubberBanded(proposed - expandedHeight)
        } else if proposed < collapsedHeight {
            return collapsedHeight - rubberBanded(collapsedHeight - proposed)
        }
        return proposed
    }

    private func rubberBanded(_ overshoot: CGFloat) -> CGFloat {
        let coefficient: CGFloat = 0.55
        return (1 - 1 / ((overshoot * coefficient / travelRange) + 1)) * travelRange * 0.3
    }

    var body: some View {
        Group {
            if isMinimized {
                minimizedBar
            } else {
                sheetContent
                    .simultaneousGesture(dragGesture)
            }
        }
        // Saat minimized kita pakai `minimizedHeight` langsung (bukan`liveHeight`),
        .frame(height: isMinimized ? minimizedHeight : liveHeight, alignment: .top)
        .clipped()
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
    }

    /// Tampilan bar kecil saat sheet di-minimize.
    /// Tap di mana saja pada bar ini -> sheet dibuka lagi (kembali ke collapsed).
    private var minimizedBar: some View {
        Button(action: restore) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Directions")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(destinationTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 8)
                    
                    // Tombol X di mode minimized, untuk yang mau menutup total.
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(8)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, minHeight: minimizedHeight)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }

    /// Keluar dari mode minimized, sheet kembali muncul penuh (collapsed).
    private func restore() {
        withAnimation(sheetSpring) {
            isMinimized = false
        }
    }

    private var sheetContent: some View {
        DirectionsSheetContent(
            originTitle: originTitle,
            destinationTitle: destinationTitle,
            selectedKind: selectedKind,
            options: options,
            onSelectOption: onSelectOption,
            showLegend: showLegend,
            onClose: onClose,
            onEditDestination: onEditDestination,
            onStart: onStart
        )
        .drawingGroup()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                dragTranslation = value.translation.height
            }
            .onEnded(handleDragEnd)
    }

    private func handleDragEnd(_ value: DragGesture.Value) {
        let translation = value.translation.height
        let velocity = value.velocity.height
        let distanceThreshold = travelRange * 0.3
        let flickVelocity: CGFloat = 700

        let draggedUpEnough = translation < -distanceThreshold || velocity < -flickVelocity
        let draggedDownEnough = translation > distanceThreshold || velocity > flickVelocity

        withAnimation(sheetSpring) {
            if !isExpanded && draggedUpEnough {
                onExpand()
            } else if isExpanded && draggedDownEnough {
                onCollapse()
            } else if !isExpanded && draggedDownEnough {
                isMinimized = true
            }
            dragTranslation = 0
        }
    }

    private let sheetSpring: Animation = .spring(response: 0.38, dampingFraction: 0.9)
}

// MARK: - Directions sheet content (diisolasi dari state drag)

private struct DirectionsSheetContent: View {
    let originTitle: String
    let destinationTitle: String
    let selectedKind: String
    let options: [RouteOption]
    var onSelectOption: (RouteOption) -> Void
    let showLegend: Bool
    var onClose: () -> Void
    var onEditDestination: () -> Void
    var onStart: (RouteOption) -> Void

    private var recommendedOption: RouteOption? {
        options.first(where: { $0.isRecommended })
    }

    private var chosenOption: RouteOption? {
        options.first(where: { $0.kind == selectedKind })
    }

    private var orderedOptions: [RouteOption] {
        guard let primary = chosenOption ?? recommendedOption else { return options }
        let rest = options.filter { $0.id != primary.id }
        return [primary] + rest
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            LocationInputStack(
                originTitle: originTitle,
                destinationTitle: destinationTitle,
                // Origin ("My Location") sengaja belum bisa di-tap untuk saat ini —
                // fitur ganti titik awal belum didukung. Tinggal ganti `nil` di bawah
                // jadi `onEditOrigin` kalau nanti fiturnya sudah siap.
                onSelectOrigin: nil,
                onSelectDestination: onEditDestination
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 1)

            if showLegend {
                RouteLegendView()
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
            }

            routeOptionsSection
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

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
        }
    }

    @ViewBuilder
    private var routeOptionsSection: some View {
        if orderedOptions.isEmpty {
            Spacer(minLength: 12)
        } else {
            VStack(spacing: 14) {
                ForEach(orderedOptions) { option in
                    RouteOptionsCard(
                        option: option,
                        isSelected: option.kind == selectedKind,
                        onSelect: { onSelectOption(option) },
                        onStart: { onStart(option) }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Route option card

struct RouteOptionsCard: View {
    let option: RouteOption
    var isSelected: Bool = false
    var onSelect: () -> Void = {}
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
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onSelect)
    }
}

/// Tombol "Start" di dalam RouteOptionsCard.
private struct StartButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("Start")
//                Image(systemName: "chevron.forward.2")
//                    .font(.system(size: 13))
            }
            .frame(height: 40)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .cornerRadius(15)
            //.clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Collapsed") {
    DirectionsSheet(
        originTitle: "My Location",
        destinationTitle: "The Breeze",
        selectedKind: RouteOption.sample.first?.kind ?? "",
        options: RouteOption.sample,
        onSelectOption: { print("selected: \($0.title)") },
        showLegend: true,
        isExpanded: false,
        collapsedHeight: 260,
        expandedHeight: 700,
        onClose: {},
        onExpand: {},
        onCollapse: {},
        onEditOrigin: {},
        onEditDestination: {},
        onStart: { print("start: \($0.title)") }
    )
}

#Preview("Expanded") {
    DirectionsSheet(
        originTitle: "My Location",
        destinationTitle: "The Breeze",
        selectedKind: RouteOption.sample.first?.kind ?? "",
        options: RouteOption.sample,
        onSelectOption: { print("selected: \($0.title)") },
        showLegend: true,
        isExpanded: true,
        collapsedHeight: 260,
        expandedHeight: 700,
        onClose: {},
        onExpand: {},
        onCollapse: {},
        onEditOrigin: {},
        onEditDestination: {},
        onStart: { print("start: \($0.title)") }
    )
}
