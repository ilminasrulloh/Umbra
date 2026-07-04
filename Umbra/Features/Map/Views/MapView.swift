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
    @State private var locationManager = UserLocationManager()
    @State private var weatherManager = WeatherManager()
    @State private var routeMapManager = RouteMapManager()
    
    @State private var expandUVIndexButton = false
    @State private var expandWeatherButton = false
    
    @State private var pingWeatherManager = false
    
    @State private var showBottomPanelSheet = true
    @State private var currentPresentationDetents: PresentationDetent = .fraction(0.1)
    
    @State private var userCurrentPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    
    @State private var userOriginText = ""
    @State private var userDestinationText = ""
    @State private var showDestination = true
    @FocusState private var clickedTextField: Field?
    
    var body: some View {
        Map(position: $userCurrentPosition) {
            UserAnnotation()
        }
        .ignoresSafeArea()
        .onAppear {
            locationManager.RequestUserLocation()
        }
        .onChange(of: locationManager.userLocation) { newLocation in
            if let location = newLocation {
                if pingWeatherManager {
                    Task {
                        await weatherManager.GetCurrentWeather(for: location)
                    }
                }
            }
        }
        .sheet(isPresented: $showBottomPanelSheet) {
            BottomPanelSheetView(
                currentPresentationDetents: $currentPresentationDetents,
                userOrigin: $userOriginText,
                userDestination: $userDestinationText,
                routeMapManager: $routeMapManager,
                showDestination: $showDestination,
                focusedField: $clickedTextField
            )
            .interactiveDismissDisabled()
            .presentationDetents([.fraction(0.1), .large], selection: $currentPresentationDetents)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
        }
        .overlay(alignment: .topLeading){
            weatherAndUVIndexView(expandUVIndexButton: $expandUVIndexButton, expandWeatherButton: $expandWeatherButton, weatherManager: weatherManager)
        }
    }
}

struct weatherAndUVIndexView: View {
    @Binding var expandUVIndexButton: Bool
    @Binding var expandWeatherButton: Bool
    
    var weatherManager: WeatherManager
    
    var body: some View {
        HStack (alignment: .top) {
            Button(action: {expandWeatherButton.toggle()}) {
                if expandWeatherButton {
                    VStack (alignment: .leading) {
                        HStack {
                            Image(systemName: weatherManager.weatherSymbolName)
                                .padding(.trailing, 5)
                            Text(weatherManager.temperature)
                        }
                        Text(weatherManager.feelsLike)
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
                        Image(systemName: weatherManager.weatherSymbolName)
                            .padding(.trailing, 5)
                        Text(weatherManager.temperature)
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
                            Text("\(weatherManager.uvIndex)")
                        }
                        Text(weatherManager.uvCategory)
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
                        Text("\(weatherManager.uvIndex)")
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

struct BottomPanelSheetView: View {
    @Binding var currentPresentationDetents: PresentationDetent
    @Binding var userOrigin: String
    @Binding var userDestination: String
    
    @Binding var routeMapManager: RouteMapManager
    @Binding var showDestination: Bool
    
    var focusedField: FocusState<Field?>.Binding
    var isExtended: Bool { currentPresentationDetents == .large}
    
    var body: some View {
        VStack (alignment: .leading) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search Destination", text: $userDestination)
                        .disabled(!isExtended)
                        .focused(focusedField, equals: .destination)
                        .onChange(of: $userDestination.wrappedValue) { newUserDestination in
                            if showDestination {
                                routeMapManager.SearchLocation(query: newUserDestination)
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
                    
                    
                    if isExtended && !userDestination.isEmpty {
                        Button(action: {routeMapManager.clearField(text:$userDestination)}) {
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
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
            }
            .padding(isExtended ? 20 : 0)
            
            if isExtended {
                if userDestination.isEmpty {
                    Text("Nearby")
                        .fontWeight(.medium)
                        .padding(.leading, 20)
                    
                    Spacer()
                } else {
                    ScrollView {
                        LocationSuggestionListView(routeMapManager: $routeMapManager)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct LocationSuggestionListView: View {
    @Binding var routeMapManager: RouteMapManager
    
    var body: some View {
        VStack (spacing: 0) {
            ForEach(routeMapManager.results, id: \.self) { result in
                Button {
                    routeMapManager.MoveToSelectedLocation(completion: result)
                } label: {
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
                                
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Color(.systemGray6))
                    
                }
                
            }
        }
        .cornerRadius(20)
        .padding(.horizontal, 30)
    }
}

#Preview {
    MapView()
}
