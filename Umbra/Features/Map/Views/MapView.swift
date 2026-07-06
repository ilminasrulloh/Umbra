//
//  MapView.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 01/07/26.
//

import SwiftUI
import Combine
import MapKit
import WeatherKit

enum Field: Hashable {
    case origin
    case destination
}

struct MapView: View {
    @State private var viewModel = MapViewModel()
    
    @State var expandUVIndexButton = false
    @State var expandWeatherButton = false
    @State var showBottomPanelSheet = true
    @State var currentPresentationDetents: PresentationDetent = .fraction(0.1)
    
    @FocusState var clickedTextField: Field?
    
    var body: some View {
        Map(position: $viewModel.userCurrentPosition) {
            UserAnnotation()
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.RequestUserLocation()
        }
        .onChange(of: viewModel.locationManager.userLocation) { oldValue, newLocation in
            if let location = newLocation, viewModel.pingWeatherManager {
                Task {
                    await viewModel.GetCurrentWeather(for: location)
                }
            }
            
        }
        .sheet(isPresented: $showBottomPanelSheet) {
            BottomPanelSheetView(
                viewModel: viewModel,
                currentPresentationDetents: $currentPresentationDetents,
                focusedField: $clickedTextField
            )
            .interactiveDismissDisabled()
            .presentationDetents([.fraction(0.1), .large], selection: $currentPresentationDetents)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
        }
        .overlay(alignment: .topLeading) {
            weatherAndUVIndexView(
                viewModel: viewModel,
                expandUVIndexButton: $expandUVIndexButton,
                expandWeatherButton: $expandWeatherButton
            )
        }
    }
}

struct BottomPanelSheetView: View {
    @Bindable var viewModel: MapViewModel
    @Binding var currentPresentationDetents: PresentationDetent
    var focusedField: FocusState<Field?>.Binding
    
    var isExtended: Bool { currentPresentationDetents == .large}
    
    var body: some View {
        VStack (alignment: .leading) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search Destination", text: $viewModel.userDestinationText)
                        .disabled(!isExtended)
                        .focused(focusedField, equals: .destination)
                        .onChange(of: $viewModel.userDestinationText.wrappedValue) { newUserDestination in
                            if viewModel.showDestination {
                                viewModel.SearchLocation(query: newUserDestination)
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
                                            focusedField.wrappedValue = .destination
                                        }
                                    }
                            }
                        }
                    
                    
                    if isExtended && !(viewModel.userDestinationText).isEmpty {
                        Button(action: {
                            viewModel.userDestinationText = ""
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
                            .foregroundStyle(Color(.black), Color(.systemGray3))
                            
                    }
                }
            }
            .padding(isExtended ? 20 : 0)
            
            if isExtended {
                if viewModel.userDestinationText.isEmpty {
                    Text("Nearby")
                        .fontWeight(.medium)
                        .padding(.leading, 20)
                    
                    Spacer()
                } else {
                    ScrollView {
                        VStack (spacing: 0) {
                            ForEach(viewModel.results, id: \.self) { result in
                                LocationSuggestionView(
                                    viewModel: viewModel,
                                    result: result
                                )
                                
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct LocationSuggestionView: View {
    @Bindable var viewModel: MapViewModel
    var result: MKLocalSearchCompletion
    
    var body: some View {
        Button {
            
        } label : {
            VStack (alignment: .leading, spacing: 2){
                HStack (spacing: 2){
                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(Color(.white))
                                .font(.system(size: 14))
                        )
                        .padding(.trailing, 20)
                    
                    VStack (alignment: .leading) {
                        Text(result.title)
                            .foregroundStyle(Color(.black))
                        HStack {
                            Text("Distance")
                            Text("•")
                            Text("Alamat")
                        }
                        .foregroundStyle(Color(.systemGray2))
                    }
                }
                
                if viewModel.results.first == result  {
                    Button {
                    
                    } label  : {
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
        .padding(.bottom, viewModel.results.first == result ? 8 : 0)
        .padding(.horizontal, 30)
    }
}

struct weatherAndUVIndexView: View {
    @Bindable var viewModel: MapViewModel
    @Binding var expandUVIndexButton: Bool
    @Binding var expandWeatherButton: Bool
    
    var body: some View {
        HStack (alignment: .top) {
            Button(action: {expandWeatherButton.toggle()}) {
                if expandWeatherButton {
                    VStack (alignment: .leading) {
                        HStack {
                            Image(systemName: viewModel.weatherSymbolName)
                                .padding(.trailing, 5)
                            Text(viewModel.temperature)
                        }
                        Text(viewModel.feelsLike)
                            .padding(.top, 2)
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.leading, 20)
                    .padding(.trailing, 30)
                    .background(.ultraThickMaterial)
                    .cornerRadius(20)
                    .padding(.leading, 20)
                    .padding(.trailing, 10)
                    
                } else {
                    HStack {
                        Image(systemName: viewModel.weatherSymbolName)
                            .padding(.trailing, 5)
                        Text(viewModel.temperature)
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 20)
                    .background(.ultraThickMaterial)
                    .cornerRadius(25)
                    .padding(.leading, 20)
                    .padding(.trailing, 10)
                }
            }
            
            
            Button(action: {expandUVIndexButton.toggle()}) {
                if expandUVIndexButton {
                    VStack (alignment: .leading) {
                        HStack {
                            Image(systemName: "sun.min")
                                .padding(.trailing, 5)
                            Text("\(viewModel.uvIndex)")
                        }
                        Text(viewModel.uvCategory)
                            .font(.caption)
                            .foregroundStyle(Color(.systemGray))
                        Text("Use Sunscreen")
                            .font(.default)
                            .foregroundStyle(Color(.systemGray))
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.leading, 20)
                    .padding(.trailing, 30)
                    .background(.ultraThickMaterial)
                    .cornerRadius(20)
                    .padding(.leading, 10)
                    
                } else {
                    HStack {
                        Image(systemName: "sun.min")
                            .padding(.trailing, 5)
                        Text("\(viewModel.uvIndex)")
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 20)
                    .background(.ultraThickMaterial)
                    .cornerRadius(25)
                    .padding(.leading, 10)
                }
            }
        }
        .foregroundStyle(Color(.black))
    }
}

#Preview {
    MapView()
}
