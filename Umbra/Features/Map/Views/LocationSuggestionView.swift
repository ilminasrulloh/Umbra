//
//  LocationSuggestionView.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI
import MapKit

struct LocationSuggestionView: View {
    @Bindable var viewModel: MapViewModel
    @State private var distanceText: String = ""
    var result: MKLocalSearchCompletion
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
                        Text(result.title)
                            .foregroundStyle(.primary)
                        Text(result.subtitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(Color(.systemGray2))
                            .font(.subheadline)
                    }
                }
                
                if viewModel.results.first == result {
                    Button {
                        selectDestination()
                    } label: {
                        Text("See Routes")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(Color(.white))
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color(.blue))
                            .cornerRadius(25)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                
                Divider()
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.horizontal, 20)
            .background(Color(.systemGray6))
        }
        .cornerRadius(20)
        .padding(.bottom, viewModel.results.first == result ? 8 : 4)
        .padding(.horizontal, 30)
    }
    
    private func selectDestination() {
        Task {
            if let destination = await viewModel.resolveDestination(for: result) {
                onSeeRoutes(destination)
            }
        }
    }
}
