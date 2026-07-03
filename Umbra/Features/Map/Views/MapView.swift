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

struct MapView: View {
    @State private var locationManager = UserLocationManager()
    @State private var weatherManager = WeatherManager()
    
    @State private var expandUVIndexButton = false
    @State private var expandWeatherButton = false
    
    @State private var pingWeatherManager = false
    
    @State private var showBottomPanelSheet = true
    @State private var currentPresentationDetents: PresentationDetent = .fraction(0.1)
    
    @State private var userCurrentPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    
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
            BottomPanelSheetView(currentPresentationDetents: $currentPresentationDetents)
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
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            Text("Search Destination")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .padding(.trailing, 200)
        .background(Color(.tertiarySystemFill))
        .foregroundStyle(Color(.secondaryLabel))
        .cornerRadius(30)
        
        .onTapGesture {
            currentPresentationDetents = .large
        }
    }
    
}

#Preview {
    MapView()
}
