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

enum DirectionsSheetState: Equatable {
    case hidden
    case collapsed
    case expanded
}

struct MapView: View {
    @State private var locationManager = UserLocationManager()
    @State private var weatherManager = WeatherManager()
    @State private var routeMapManager = RouteMapManager()
    @State private var options = RouteOption.sample
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

    // Single source of truth for which "page" of the directions flow is showing.
    @State private var directionsSheetState: DirectionsSheetState = .hidden

    // Fixed height for the collapsed (Gambar 2) sheet.
    private let collapsedSheetHeight: CGFloat = 260

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Replace with your real MapKit / MapView here.
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
                        focusedField: $clickedTextField,
                        onSeeRoutes: {
                            // Gambar 1 -> Gambar 2: sembunyikan search sheet,
                            // tampilkan Directions sheet dalam mode collapsed.
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                showBottomPanelSheet = false
                                directionsSheetState = .collapsed
                            }
                        }
                    )
                    .interactiveDismissDisabled()
                    .presentationDetents([.fraction(0.1), .large], selection: $currentPresentationDetents)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled)
                }
                .overlay(alignment: .topLeading) {
                    weatherAndUVIndexView(expandUVIndexButton: $expandUVIndexButton, expandWeatherButton: $expandWeatherButton, weatherManager: weatherManager)
                }

                // Callout bubble for the recommended route (muncul di kedua state collapsed & expanded)
                if directionsSheetState != .hidden, let recommended = options.first(where: { $0.isRecommended }) {
                    VStack {
                        Spacer()
                        RouteCalloutBubble(option: recommended)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    }
                }

                if directionsSheetState != .hidden {
                    VStack {
                        Spacer()
                        DirectionsSheet(
                            originTitle: "My Location",
                            destinationTitle: "The Breeze",
                            options: options,
                            showLegend: true,
                            isExpanded: directionsSheetState == .expanded,
                            // Near-full-screen when expanded, computed from the
                            // actual screen height instead of a fixed number.
                            collapsedHeight: collapsedSheetHeight,
                            expandedHeight: geo.size.height * 0.92,
                            onClose: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    if directionsSheetState == .expanded {
                                        // Gambar 3 -> Gambar 2
                                        directionsSheetState = .collapsed
                                    } else {
                                        // Gambar 2 -> Gambar 1 (menu utama)
                                        directionsSheetState = .hidden
                                        currentPresentationDetents = .fraction(0.1)
                                        clickedTextField = nil
                                        showBottomPanelSheet = true
                                    }
                                }
                            },
                            onExpand: {
                                // Drag ke atas: Gambar 2 -> Gambar 3
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    directionsSheetState = .expanded
                                }
                            },
                            onCollapse: {
                                // Drag ke bawah saat expanded: Gambar 3 -> Gambar 2
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    directionsSheetState = .collapsed
                                }
                            },
                            onStart: { print("start \($0.title)") }
                        )
                        // NOTE: no .frame(height:) here anymore — DirectionsSheet
                        // now controls its own height via collapsedHeight/expandedHeight.
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 20, y: -4)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct weatherAndUVIndexView: View {
    @Binding var expandUVIndexButton: Bool
    @Binding var expandWeatherButton: Bool

    var weatherManager: WeatherManager

    var body: some View {
        HStack(alignment: .top) {
            Button(action: { expandWeatherButton.toggle() }) {
                if expandWeatherButton {
                    VStack(alignment: .leading) {
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


            Button(action: { expandUVIndexButton.toggle() }) {
                if expandUVIndexButton {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "sun.min")
                                .padding(.trailing, 5)
                            Text("\(weatherManager.uvIndex)")
                        }
                        Text(weatherManager.uvCategory)
                            .font(.caption)
                            .foregroundStyle(Color(.black))
                        Text("Use Sunscreen")
                            .font(.body)
                            .foregroundStyle(Color(.black))
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
    @State private var expandDestinationInformation: MKLocalSearchCompletion? = nil

    var focusedField: FocusState<Field?>.Binding
    /// Called when the user taps "See Routes" on a suggestion — this is the
    /// trigger that takes us from Gambar 1 to Gambar 2.
    var onSeeRoutes: () -> Void

    var isExtended: Bool { currentPresentationDetents == .large }

    var body: some View {
        VStack(alignment: .leading) {
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
                        Button(action: { routeMapManager.clearField(text: $userDestination) }) {
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
                if userDestination.isEmpty {
                    Text("Nearby")
                        .fontWeight(.medium)
                        .padding(.leading, 20)

                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(routeMapManager.results, id: \.self) { result in
                                LocationSuggestionView(
                                    result: result,
                                    expandDestinationInformation: expandDestinationInformation == result,
                                    onTap: {
                                        withAnimation {
                                            expandDestinationInformation = (expandDestinationInformation == result) ? nil : result
                                        }
                                    },
                                    onSeeRoutes: onSeeRoutes
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
    var result: MKLocalSearchCompletion
    var expandDestinationInformation: Bool
    var onTap: () -> Void
    var onSeeRoutes: () -> Void

    var body: some View {

        Button(action: onTap) {
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
                            .foregroundStyle(Color(.black))
                        HStack {
                            Text("Distance")
                            Text("•")
                            Text("Alamat")
                        }
                        .foregroundStyle(Color(.systemGray2))
                    }
                }

                if expandDestinationInformation {
                    Button(action: onSeeRoutes) {
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
        .padding(.vertical, expandDestinationInformation ? 8 : 0)
        .padding(.horizontal, 30)
    }
}


/// The speech-bubble style callout pointing at the route on the map.
private struct RouteCalloutBubble: View {
    let option: RouteOption

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.system(size: 15, weight: .bold))
                Text(option.subtitle)
                    .font(.system(size: 13))
                    .opacity(0.85)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    MapView()
}
