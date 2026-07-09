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
    @State var expandUVIndexButton = false
    @State var expandWeatherButton = false
    @State var showBottomPanelSheet = true
    @State var currentPresentationDetents: PresentationDetent = .fraction(0.1)
    @FocusState var clickedTextField: Field?
    
    let locationManager = LocationManager()
    @State private var viewModel = MapViewModel()
    
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
    
    private let collapsedSheetHeight: CGFloat = 400
    
    private var selectedOption: RouteOption? {
        viewModel.routeOptions.first(where: { $0.kind == selectedRouteKind })
    }
    
    private var coneRotationDegrees: Double? {
        guard let heading = locationManager.heading, heading.headingAccuracy >= 0 else { return nil }
        let value = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        return value
    }
    
    /// Tombol untuk mengembalikan kamera peta ke lokasi user saat ini.
    private var recenterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.userCurrentPosition = .userLocation(fallback: .automatic)
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .padding(12)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 3)
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Map(position: $viewModel.userCurrentPosition) {
                    if let userCoordinate = locationManager.userLocation?.coordinate {
                        Annotation("", coordinate: userCoordinate) {
                            UserLocationIndicator(headingDegrees: coneRotationDegrees)
                        }
                        .annotationTitles(.hidden)
                    }
                    
                    routeOverlay
                    
                    
                    if let destination = resolvedDestination {
                        Marker(destination.title, coordinate: destination.coordinate)
                            .tint(.red)
                    }
                    
                    if let origin = resolvedOrigin {
                        Marker(origin.title, coordinate: origin.coordinate)
                            .tint(.green)
                    }
                    
                    ForEach(orderedRouteOptions, id: \.kind) { option in
                        if let coordinate = viewModel.midpointCoordinate(for: option.kind) {
                            Annotation("", coordinate: coordinate, anchor: .top) {
                                RouteCalloutBubble(option: option, isSelected: option.kind == selectedRouteKind)
                                // UBAH NILAI 0.4 MENJADI 0.75 ATAU 0.8 DI SINI
                                    .scaleEffect(max(0.75, min(1.0, 3000 / cameraDistance)))
                                    .animation(.interactiveSpring, value: cameraDistance)
                                    .onTapGesture {
                                        withAnimation(.spring(duration: 0.3)) {
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
                    viewModel.requestUserLocation()
                }
                .onChange(of: viewModel.locationManager.userLocation) {_, newLocation in
                    if let location = newLocation, viewModel.pingWeatherManager {
                        Task {
                            await viewModel.getCurrentWeather(for: location)
                        }
                    }
                }
                .onChange(of: viewModel.routeOptions) { _, newOptions in
                    if newOptions.count == 1, let onlyOption = newOptions.first {
                        selectedRouteKind = onlyOption.kind
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
                    WeatherAndUVIndexView(
                        viewModel: viewModel,
                        expandUVIndexButton: $expandUVIndexButton,
                        expandWeatherButton: $expandWeatherButton
                    )
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        recenterButton
                            .padding(.trailing, 20)
                            .padding(
                                .bottom,
                                directionsSheetState != .hidden
                                ? collapsedSheetHeight + 16
                                : geo.size.height * 0.1 + 16
                            )
                    }
                }
                
                if directionsSheetState != .hidden {
                    VStack {
                        Spacer()
                        DirectionsSheet(
                            originTitle: resolvedOrigin?.title ?? "My Location",
                            destinationTitle: resolvedDestination?.title ?? "Tujuan",
                            selectedKind: selectedRouteKind,
                            options: viewModel.routeOptions,
                            onSelectOption: { option in
                                selectedRouteKind = option.kind
                            },
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
                                selectedRouteKind = "shaded"
                                viewModel.results = []
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
                selectedRouteKind: selectedRouteKind,
                onArrivalDismissed: {
                    // Sama seperti reset di onClose DirectionsSheet — supaya begitu
                    // kembali dari NavigateView, MapView bersih lagi (cuma lokasi
                    // user terkini), tidak ada sisa rute/marker/destinasi lama.
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
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
            )
        }
    }
    
    @MapContentBuilder
    private var routeOverlay: some MapContent {
        if let route = viewModel.calculatedRoutes.first {
            MapPolyline(route.polyline)
                .stroke(.yellow,
                        lineWidth: selectedRouteKind == "fastest" ? 6 : 2)
        }
        
        if let route = viewModel.shadedRoute, !route.coordinates.isEmpty {
            ForEach(route.segments) { segment in
                
                let polyline = MapPolyline(coordinates: segment.coordinate)
                let strokeWidth: CGFloat = selectedRouteKind == "shaded" ? 6 : 2
                
                polyline.stroke(segment.color, lineWidth: strokeWidth)
            }
        }
    }
    
    private var orderedRouteOptions: [RouteOption] {
        viewModel.routeOptions.sorted { lhs, rhs in
            (lhs.kind == selectedRouteKind ? 1 : 0) < (rhs.kind == selectedRouteKind ? 1 : 0)
        }
    }
}


private struct RouteCalloutBubble: View {
    let option: RouteOption
    var isSelected: Bool = true
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.footnote)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.kind == "fastest" ? "Standard" : option.title)
                    .font(.body)
                    .fontWeight(.bold)
                Text(option.subtitle)
                    .font(.footnote)
                    .opacity(0.85)
            }
            Spacer()
        }
        .frame(width: 150)
        .foregroundStyle(.white)
        .padding(14)
        .background(isSelected ? Color.accentColor : Color(.systemGray))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(isSelected ? 0.2 : 0.08), radius: isSelected ? 8 : 3)
        .scaleEffect(isSelected ? 1.0 : 0.75 )
        .zIndex(isSelected ? 5 : 1)
    }
}

#Preview {
    MapView()
}
