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
import CoreLocation

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
    @State private var viewModel = MapViewModel()
    @State var expandUVIndexButton = false
    @State var expandWeatherButton = false
    @State var showBottomPanelSheet = true
    @State var currentPresentationDetents: PresentationDetent = .fraction(0.1)
    @FocusState var clickedTextField: Field?
    
    @State private var directionsSheetState: DirectionsSheetState = .hidden
    @State private var options = RouteOption.sample

    /// Tujuan yang sudah di-resolve jadi koordinat asli (hasil tap "See Routes")
    @State private var resolvedDestination: NavigationDestination?

    /// Diisi saat tombol "Start" di DirectionsSheet ditekan — trigger fullScreenCover ke NavigateView
    @State private var navigateDestination: NavigationDestination?

    /// Tinggi sheet saat collapsed. Dibesarkan dari 260 -> 400 karena sekarang
    /// kartu rute yang direkomendasikan (RouteOptionCard) ikut ditampilkan
    /// walau sheet belum di-expand, jadi butuh ruang lebih supaya tidak terpotong.
    private let collapsedSheetHeight: CGFloat = 400
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Map(position: $viewModel.userCurrentPosition) {
                    UserAnnotation()

//                    if let route = viewModel.calculatedRoutes.first {
//                        MapPolyline(route.polyline)
//                            .stroke(.blue, lineWidth: 6)
//                    }

                    if let route = viewModel.shadedRoute, !route.coordinates.isEmpty {
                        MapPolyline(coordinates: route.coordinates)
                            .stroke(.blue, lineWidth: 6)
                    }
                    
                    if let destination = resolvedDestination {
                        Marker(destination.title, coordinate: destination.coordinate)
                            .tint(.red)
                    }
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
                        focusedField: $clickedTextField,
                        onSeeRoutes: { destination in
                            resolvedDestination = destination
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                showBottomPanelSheet = false
                                directionsSheetState = .collapsed
                            }
                            Task {
                                await viewModel.calculateWalkingRoute(to: destination.coordinate)
                            }
                        }
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
                            destinationTitle: resolvedDestination?.title ?? "Tujuan",
                            options: options,
                            showLegend: true,
                            isExpanded: directionsSheetState == .expanded,
                            collapsedHeight: collapsedSheetHeight,
                            expandedHeight: geo.size.height * 0.92,
                            onClose: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    if directionsSheetState == .expanded {
                                        directionsSheetState = .collapsed
                                    } else {
                                        directionsSheetState = .hidden
                                        currentPresentationDetents = .fraction(0.1)
                                        clickedTextField = nil
                                        showBottomPanelSheet = true
                                        resolvedDestination = nil
                                        viewModel.calculatedRoutes = []
                                        viewModel.shadedRoute = nil
                                    }
                                }
                            },
                            onExpand: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    directionsSheetState = .expanded
                                }
                            },
                            onCollapse: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    directionsSheetState = .collapsed
                                }
                            },
                            onStart: { _ in
                                // Rute sudah dilihat user di layar preview — sekarang pindah ke NavigateView
                                // untuk mulai navigasi langkah-demi-langkah yang sebenarnya.
                                navigateDestination = resolvedDestination
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 20, y: -4)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $navigateDestination) { destination in
            NavigateView(
                locationManager: viewModel.locationManager,
                destination: destination.coordinate,
                destinationTitle: destination.title
            )
        }
    }
}

struct BottomPanelSheetView: View {
    @Bindable var viewModel: MapViewModel
    @Binding var currentPresentationDetents: PresentationDetent
    var focusedField: FocusState<Field?>.Binding
    /// NEW: called when the user taps "See Routes" on a suggestion, dengan tujuan yang sudah di-resolve.
    var onSeeRoutes: (NavigationDestination) -> Void

    var isExtended: Bool { currentPresentationDetents == .large }
    
    var body: some View {
        VStack(alignment: .leading) {
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
                        VStack(spacing: 0) {
                            ForEach(viewModel.results, id: \.self) { result in
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
    }
}

struct LocationSuggestionView: View {
    @Bindable var viewModel: MapViewModel
    @State private var distanceText: String = ""
    var result: MKLocalSearchCompletion
    /// NEW: called when "See Routes" is tapped for this suggestion.
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
                            .foregroundStyle(Color(.black))
                        HStack {
                            Text(distanceText)
                                .layoutPriority(1)
                            Text("•")
                            Text(result.subtitle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
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
        .padding(.bottom, viewModel.results.first == result ? 8 : 0)
        .padding(.horizontal, 30)
        .task(id: ObjectIdentifier(result)){
            distanceText = await viewModel.resolveDistance(for: result)
        }
    }

    /// Resolve hasil pencarian jadi koordinat asli lewat MapViewModel,
    /// lalu teruskan ke onSeeRoutes begitu selesai.
    private func selectDestination() {
        Task {
            await viewModel.MoveToSelectedLocation(completion: result)
            if let destination = viewModel.pendingNavigationDestination {
                onSeeRoutes(destination)
            }
        }
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
struct weatherAndUVIndexView: View {
    @Bindable var viewModel: MapViewModel
    @Binding var expandUVIndexButton: Bool
    @Binding var expandWeatherButton: Bool
    
    var body: some View {
        HStack(alignment: .top) {
            Button(action: { expandWeatherButton.toggle() }) {
                if expandWeatherButton {
                    VStack(alignment: .leading) {
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
            
            
            Button(action: { expandUVIndexButton.toggle() }) {
                if expandUVIndexButton {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "sun.min")
                                .padding(.trailing, 5)
                            Text("\(viewModel.uvIndex)")
                        }
                        Text(viewModel.uvCategory)
                            .font(.caption)
                            .foregroundStyle(Color(.systemGray))
                        Text("Use Sunscreen")
                            .font(.body)
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
        .padding(.top, 55)
    }
}

#Preview {
    MapView()
}
