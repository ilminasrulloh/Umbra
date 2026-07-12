//
//  NavigationStep.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import Foundation
import MapKit

struct NavigationStep: Identifiable {
    let id = UUID()
    let instructions: String
    let distance: CLLocationDistance
    /// Titik koordinat maneuver ini — dipakai untuk memindahkan kamera saat
    /// carousel instruksi digeser ke step ini (lihat `NavigateViewModel.previewStep`).
    let coordinate: CLLocationCoordinate2D
    /// Nama asset foto entrance gedung untuk step ini (mis. step "Enter the Building").
    /// `nil` kalau step ini tidak punya foto entrance terkait.
    var entranceImageName: String? = nil
}
