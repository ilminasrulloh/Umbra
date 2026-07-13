//
//  ArrivalInfo.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import Foundation

// MARK: - Arrival hand-off

/// Data kecil yang dikirim NavigateView -> MapView lewat closure `onArrive`
/// begitu user sampai tujuan, supaya MapView bisa menampilkan bottom sheet
/// "kamu sudah sampai" setelah NavigateView menutup dirinya sendiri.
struct ArrivalInfo: Identifiable {
    let id = UUID()
    let destinationTitle: String
    let minutesOfSunAvoided: Int
}

