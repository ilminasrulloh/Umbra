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
    
    @State private var selectedRouteKind = "shaded"
    @State private var directionsSheetState: DirectionsSheetState = .hidden
    
    /// Menyimpan camera distance secara dinamis untuk auto-scaling bubble callout rute
    @State private var cameraDistance: Double = 2000
    
    /// Tujuan yang sudah di-resolve jadi koordinat asli (hasil tap "See Routes")
    @State private var resolvedDestination: NavigationDestination?
    
    /// Custom origin, hasil edit dari DirectionsSheet. nil berarti masih
    /// pakai lokasi user saat ini ("My Location").
    @State private var resolvedOrigin: NavigationDestination?
    
    /// Field mana yang lagi diedit di BottomPanelSheetView — menentukan
    /// apakah hasil "See Routes" berikutnya mengisi origin atau destination.
    @State private var editingField: Field = .destination
    
    /// Diisi saat tombol "Start" di DirectionsSheet ditekan — trigger fullScreenCover ke NavigateView
    @State private var navigateDestination: NavigationDestination?
    
    
    let locationManager = LocationManager()
    /// Tinggi sheet saat collapsed. Dibesarkan dari 260 -> 400 karena sekarang
    /// kartu rute yang direkomendasikan (RouteOptionCard) ikut ditampilkan
    /// walau sheet belum di-expand, jadi butuh ruang lebih supaya tidak terpotong.
    private let collapsedSheetHeight: CGFloat = 400
    
    private var selectedOption: RouteOption? {
        viewModel.routeOptions.first(where: { $0.kind == selectedRouteKind })
    }
    
    private var coneRotationDegrees: Double? {
        guard let heading = locationManager.heading, heading.headingAccuracy >= 0 else { return nil }
        let value = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        return value
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Map(position: $viewModel.userCurrentPosition) {
                    UserAnnotation()
                    if let userCoordinate = locationManager.userLocation?.coordinate {
                        Annotation("", coordinate: userCoordinate) {
                            UserLocationIndicator(headingDegrees: coneRotationDegrees)
                        }
                        .annotationTitles(.hidden)
                    }
                    
                    if let route = viewModel.calculatedRoutes.first {
                        MapPolyline(route.polyline)
                            .stroke(
                                selectedRouteKind == "fastest" ? .yellow : .yellow.opacity(0.3),
                                lineWidth: selectedRouteKind == "fastest" ? 6 : 3)
                    }
                    
                    if let route = viewModel.shadedRoute, !route.coordinates.isEmpty {
                        MapPolyline(coordinates: route.coordinates)
                            .stroke(
                                selectedRouteKind == "shaded" ? .blue : .blue.opacity(0.3),
                                lineWidth: selectedRouteKind == "shaded" ? 6 : 3)
                    }
                    
                    if let destination = resolvedDestination {
                        Marker(destination.title, coordinate: destination.coordinate)
                            .tint(.red)
                    }
                    
                    if let origin = resolvedOrigin {
                        Marker(origin.title, coordinate: origin.coordinate)
                            .tint(.green)
                    }
                    
                    ForEach(viewModel.routeOptions, id: \.kind) { option in
                        if let coordinate = viewModel.midpointCoordinate(for: option.kind) {
                            Annotation("", coordinate: coordinate) {
                                RouteCalloutBubble(option: option, isSelected: option.kind == selectedRouteKind)
                                    // UBAH NILAI 0.4 MENJADI 0.75 ATAU 0.8 DI SINI
                                    .scaleEffect(max(0.75, min(1.0, 3000 / cameraDistance)))
                                    .animation(.interactiveSpring, value: cameraDistance)
                                    .onTapGesture {
                                        withAnimation(.spring()) {
                                            selectedRouteKind = option.kind
                                        }
                                    }
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }
                .ignoresSafeArea()
                // Deteksi perubahan zoom level peta secara kontinu
                .onMapCameraChange(frequency: .continuous) { context in
                    cameraDistance = context.camera.distance
                }
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
                        editingField: editingField,
                        onSeeRoutes: { destination in
                            switch editingField {
                            case .origin:
                                resolvedOrigin = destination
                            case .destination:
                                resolvedDestination = destination
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                showBottomPanelSheet = false
                                directionsSheetState = .collapsed
                            }
                            guard let destinationCoordinate = resolvedDestination?.coordinate else { return }
                            Task {
                                await viewModel.calculateShadedWalkingRoute(to: destinationCoordinate)
                                await viewModel.calculateWalkingRoute(to: destinationCoordinate)
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
            
                if directionsSheetState != .hidden {
                    VStack {
                        Spacer()
                        DirectionsSheet(
                            originTitle: resolvedOrigin?.title ?? "My Location",
                            destinationTitle: resolvedDestination?.title ?? "Tujuan",
                            options: viewModel.routeOptions,
                            showLegend: true,
                            selectedKind: selectedRouteKind,
                            onSelectOption: { option in
                                selectedRouteKind = option.kind
                            },
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
                                        resolvedOrigin = nil
                                        editingField = .destination
                                        viewModel.calculatedRoutes = []
                                        viewModel.shadedRoute = nil
                                        viewModel.userDestinationText = ""
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
                            onEditOrigin: {
                                editingField = .origin
                                viewModel.userOriginText = resolvedOrigin?.title ?? ""
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    directionsSheetState = .hidden
                                    showBottomPanelSheet = true
                                    currentPresentationDetents = .large
                                }
                                clickedTextField = .origin
                            },
                            onEditDestination: {
                                editingField = .destination
                                viewModel.userDestinationText = resolvedDestination?.title ?? ""
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    directionsSheetState = .hidden
                                    showBottomPanelSheet = true
                                    currentPresentationDetents = .large
                                }
                                clickedTextField = .destination
                            },
                            onStart: { option in
                                selectedRouteKind = option.kind
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
                destinationTitle: destination.title,
                selectedRouteKind: selectedRouteKind
            )
        }
    }
}

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
                                viewModel.SearchLocation(query: newQuery)
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
                            .foregroundStyle(Color(.black), Color(.systemGray3))
                    }
                }
            }
            .padding(isExtended ? 20 : 0)
            
            if isExtended {
                if activeSearchText.wrappedValue.isEmpty {
                    Text("Nearby")
                        .fontWeight(.medium)
                        .padding(.leading, 20)
                    
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
    }
}

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
                            .foregroundStyle(Color(.black))
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
        .padding(.bottom, viewModel.results.first == result ? 8 : 0)
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

private struct RouteCalloutBubble: View {
    let option: RouteOption
    var isSelected: Bool = true
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.system(size: 10, weight: .bold))
                Text(option.subtitle)
                    .font(.system(size: 8))
                    .opacity(0.85)
            }
            Spacer()
        }
        .frame(width: 100)
        .foregroundStyle(.white)
        .padding(14)
        .background(isSelected ? Color.accentColor : Color(.systemGray))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(isSelected ? 0.2 : 0.08), radius: isSelected ? 8 : 3)
        .scaleEffect(isSelected ? 1.0 : 0.92)
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
