//
//  NearbyPlaceSuggestionView.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI
import MapKit

struct NearbyLocationView: View {
    @Bindable var viewModel: MapViewModel
    var result: MKMapItem
    var onSeeRoutes: (NavigationDestination) -> Void
    
    var body: some View {
        Button {
            selectDestination()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(Color(.white))
                                .font(.system(size: 14))
                        )
                        .padding(.trailing, 20)
                    
                    VStack(alignment: .leading) {
                        Text(result.name ?? "Unknown")
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(result.placemark.title ?? "")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(Color(.systemGray2))
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                }
//
                Divider()
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.horizontal, 20)
            .background(Color(.systemGray6))
        }
        .cornerRadius(20)
//        .padding(.bottom, 4)
        .padding(.horizontal, 30)
    }
    
    private func selectDestination() {
        let destination = NavigationDestination(
            coordinate: result.placemark.coordinate,
            title: result.name ?? "Unknown"
        )
        onSeeRoutes(destination)
    }
}
