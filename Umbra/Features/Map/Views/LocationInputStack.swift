//
//  LocationInputStack.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI

/// Origin + destination dalam satu card dengan divider di tengah.
/// Tiap baris jadi bisa di-tap kalau closure-nya diisi (dipakai DirectionsSheet
/// untuk buka ulang search sheet); kalau nil, baris tetap statis (dipakai di tempat
/// yang cuma perlu menampilkan, bukan mengedit).
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
            Button(action: action) {
                LocationRow(kind: kind, title: title, isInteractive: true)
            }
            .buttonStyle(.plain)
        } else {
            LocationRow(kind: kind, title: title, isInteractive: false)
        }
    }
}
