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
    var onShowDetails: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            grabber
                .onTapGesture { toggle() }
            
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(etaMinutesText)
                    .font(.system(size: 30, weight: .bold))
                Text("mins")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 4)
            
            HStack {
                Text("\(arrivalTimeText) • \(remainingDistanceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, isExpanded ? 12 : 20)
            
            if isExpanded {
                
                detailsButton
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                Button(role: .destructive) {
                    onEndRoute()
                } label: {
                    Label("End Route", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.15), radius: 10, y: -2)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height < -18 {
                        setExpanded(true)
                    } else if value.translation.height > 18 {
                        setExpanded(false)
                    }
                }
        )
    }
    
    private var detailsButton: some View {
        Button(action: onShowDetails) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .semibold))
                Text("Details")
                    .font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    private var grabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 40, height: 5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }
    
    private func toggle() {
        setExpanded(!isExpanded)
    }
    
    private func setExpanded(_ expanded: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isExpanded = expanded
        }
    }
}
