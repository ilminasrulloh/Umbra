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
    @StateObject private var locationManager = UserLocationManager()
    
    @State private var expandUVIndexButton = false
    @State private var expandWeatherButton = false
    @State private var showBottomPanelSheet = true
    @State private var userCurrentPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    
    var body: some View {
        Map(position: $userCurrentPosition) {
            UserAnnotation()
        }
        .ignoresSafeArea()
        .onAppear {
            locationManager.RequestUserLocation()
        }
        
        .sheet(isPresented: $showBottomPanelSheet) {
            BottomPanelSheetView()
                .interactiveDismissDisabled()
                .presentationDetents([.fraction(0.1), .fraction(0.20)])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
        }
        .overlay(alignment: .topLeading){
            weatherAndUVIndexView(expandUVIndexButton: $expandUVIndexButton, expandWeatherButton: $expandWeatherButton)
        }
        
    }
}

struct weatherAndUVIndexView: View {
    @Binding var expandUVIndexButton: Bool
    @Binding var expandWeatherButton: Bool
    
    var body: some View {
        HStack (alignment: .top) {
            Button(action: {expandWeatherButton.toggle()}) {
                if expandWeatherButton {
                    VStack (alignment: .leading) {
                        HStack {
                            Image(systemName: "cloud.sun")
                                .padding(.trailing, 5)
                            Text("27°")
                        }
                        Text("Feels like 32°")
                            .padding(.top, 2)
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.leading, 20)
                    .padding(.trailing, 30)
                    .background(.ultraThickMaterial)
                    .cornerRadius(20)
                    .padding(.horizontal, 20)
                    
                } else {
                    HStack {
                        Image(systemName: "cloud.sun")
                            .padding(.trailing, 5)
                        Text("27°")
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 20)
                    .background(.ultraThickMaterial)
                    .cornerRadius(25)
                    .padding(.horizontal, 20)
                }
            }
            
            
            Button(action: {expandUVIndexButton.toggle()}) {
                if expandUVIndexButton {
                    VStack (alignment: .leading) {
                        HStack {
                            Image(systemName: "sun.min")
                                .padding(.trailing, 5)
                            Text("3")
                        }
                        Text("Moderate UV Index")
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
                    .padding(.horizontal, 20)
                    
                } else {
                    HStack {
                        Image(systemName: "sun.min")
                            .padding(.trailing, 5)
                        Text("3")
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 20)
                    .background(.ultraThickMaterial)
                    .cornerRadius(25)
                    .padding(.horizontal, 20)
                }
            }
        }
        .foregroundStyle(Color(.black))
    }
}

struct BottomPanelSheetView: View {
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            Text("Destination")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .padding(.trailing, 200)
        .background(Color(.tertiarySystemFill))
        .foregroundStyle(Color(.secondaryLabel))
        .cornerRadius(30)
        
    }
    
}

#Preview {
    MapView()
}
