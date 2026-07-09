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
    
    /// X button tapped, atau drag ke bawah saat sudah collapsed.
    var onClose: () -> Void
    
    /// Drag ke atas melewati midpoint saat collapsed -> parent pindah ke expanded.
    var onExpand: () -> Void
    
    /// Drag ke bawah melewati midpoint saat expanded -> parent pindah ke collapsed.
    var onCollapse: () -> Void
    
    /// Baris origin di-tap -> parent buka lagi search sheet untuk ganti titik awal.
    var onEditOrigin: () -> Void
    
    /// Baris destination di-tap -> parent buka lagi search sheet untuk ganti tujuan.
    var onEditDestination: () -> Void
    
    var onStart: (RouteOption) -> Void
    
    @GestureState private var dragState: CGFloat = 0
    
    private var baseHeight: CGFloat { isExpanded ? expandedHeight : collapsedHeight }
    
    private var liveHeight: CGFloat {
        min(max(baseHeight - dragState, collapsedHeight), expandedHeight)
    }
    
    private var recommendedOption: RouteOption? {
        options.first(where: { $0.isRecommended })
    }
    
    private var chosenOption: RouteOption? {
        options.first(where: { $0.kind == selectedKind })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Grabber + header — tetap ada secara visual sebagai penanda area drag,
            // tapi gesture-nya sekarang dipasang di seluruh VStack di bawah (lihat
            // .simultaneousGesture di akhir body), bukan cuma di sini.
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
        .frame(height: liveHeight, alignment: .top)
        .clipped()
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        // simultaneousGesture (bukan .gesture biasa) supaya drag ini tetap jalan
        // berbarengan dengan gesture bawaan ScrollView & Button di dalam panel —
        // tap tombol/kartu tetap berfungsi normal, scroll list rute (saat expanded)
        // juga tetap jalan.
        .simultaneousGesture(dragGesture)
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .updating($dragState) { value, state, _ in
                let raw = value.translation.height
                let deadZone: CGFloat = 4
                state = abs(raw) < deadZone ? 0 : (raw > 0 ? raw - deadZone : raw + deadZone)
            }
            .onEnded { value in
                let translation = value.translation.height
                let threshold: CGFloat = 60 // jarak menarik minimum biar dianggap sengaja
                
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    if translation < -threshold {
                        if !isExpanded { onExpand() }
                    } else if translation > threshold {
                        if isExpanded {
                            onCollapse()
                        } else {
                            onClose()
                        }
                    }
                }
            }
    }
    
    /// Opsi berikutnya (selain yang sedang dipilih) — dipakai untuk "mengintip"
    /// sedikit di bawah kartu utama saat collapsed, sebagai penanda visual bahwa
    /// masih ada opsi lain kalau panel di-swipe up.
    private var peekOption: RouteOption? {
        let primary = chosenOption ?? recommendedOption
        return options.first(where: { $0.id != primary?.id })
    }
    
    @ViewBuilder
    private var routeOptionsSection: some View {
        if isExpanded {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(options) { option in
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
        } else if let chosen = chosenOption ?? recommendedOption {
            VStack(spacing: 14) {
                RouteOptionsCard(
                    option: chosen,
                    isSelected: true,
                    onSelect: { onSelectOption(chosen) },
                    onStart: { onStart(chosen) }
                )
                
                // Sengaja dibiarkan "kepotong" oleh .clipped() di collapsedHeight —
                // cuma bagian atasnya yang keintip, jadi user sadar ada opsi lain
                // di bawah kalau panel ditarik ke atas.
                if let peek = peekOption {
                    RouteOptionsCard(
                        option: peek,
                        isSelected: false,
                        onSelect: { onSelectOption(peek) },
                        onStart: { onStart(peek) }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        } else {
            Spacer(minLength: 12)
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
                    Text(option.kind == "fastest" ? "Standard" : option.title)
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
