//
//  BottomPanelSheetView.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI

struct BottomPanelSheetView: View {
    @Bindable var viewModel: MapViewModel
    @Binding var currentPresentationDetents: PresentationDetent
    var focusedField: FocusState<Field?>.Binding
    var editingField: Field
    var onSeeRoutes: (NavigationDestination) -> Void
    
    var isExtended: Bool { currentPresentationDetents == .large }
    
    private var activeSearchText: Binding<String> {
        editingField == .origin ? $viewModel.userOriginText : $viewModel.userDestinationText
    }
    
    private var searchPlaceholder: String {
        editingField == .origin ? "Search Origin" : "Search Destination"
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField(searchPlaceholder, text: activeSearchText)
                        .disabled(!isExtended)
                        .focused(focusedField, equals: editingField)
                        .onChange(of: activeSearchText.wrappedValue) { newQuery in
                            if viewModel.showDestination {
                                viewModel.searchLocation(query: newQuery)
                            }
                        }
                        .overlay {
                            if !isExtended {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation {
                                            currentPresentationDetents = .large
                                        } completion: {
                                            focusedField.wrappedValue = editingField
                                        }
                                    }
                            }
                        }
                    
                    if isExtended && !activeSearchText.wrappedValue.isEmpty {
                        Button(action: {
                            activeSearchText.wrappedValue = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .frame(maxWidth: isExtended ? .infinity : 350)
                .background(Color(.tertiarySystemFill))
                .cornerRadius(30)
                
                if isExtended {
                    Button(action: {
                        focusedField.wrappedValue = nil
                        currentPresentationDetents = .fraction(0.1)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .fontWeight(.light)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, Color(.systemGray4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, isExtended ? 20 : 0)
            .padding(.top, isExtended ? 20 : 0)
            .padding(.bottom, isExtended ? 10 : 0)
            
            if isExtended {
                if activeSearchText.wrappedValue.isEmpty {
                    Text("Nearby")
                        .fontWeight(.medium)
                        .padding(.leading, 20)
                    
                    ForEach(viewModel.nearbyResults.prefix(3), id: \.stableID) { result in
                        NearbyLocationView(
                            viewModel: viewModel,
                            result: result,
                            onSeeRoutes: onSeeRoutes
                        )
                    }
                    
                    Spacer()
                    
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(viewModel.results, id: \.stableID) { result in
                                LocationSuggestionView(
                                    viewModel: viewModel,
                                    result: result,
                                    onSeeRoutes: onSeeRoutes
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task{
            await viewModel.getNearbyPlaces()
        }
    }
}

