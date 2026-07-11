//
//  LocationInputStack.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI

struct LocationInputStack: View {
    let originTitle: String
    let destinationTitle: String
    var onSelectOrigin: (() -> Void)? = nil
    var onSelectDestination: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            row(kind: .origin, title: originTitle, action: onSelectOrigin)
            Divider().padding(.leading, 54)
            row(kind: .destination, title: destinationTitle, action: onSelectDestination)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func row(kind: LocationRow.Kind, title: String, action: (() -> Void)?) -> some View {
        if let action {
            LocationRow(kind: kind, title: title, isInteractive: true)
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                // .onTapGesture tidak otomatis dianggap VoiceOver sebagai "button" seperti Button
                // trait ini supaya semantik aksesibilitasnya tetap sama.
                .accessibilityAddTraits(.isButton)
        } else {
            LocationRow(kind: kind, title: title, isInteractive: false)
        }
    }
}
