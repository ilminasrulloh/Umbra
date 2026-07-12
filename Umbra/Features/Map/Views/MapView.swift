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
    @State var showBottomPanelSheet = true
    @State var currentPresentationDetents: PresentationDetent = .fraction(0.1)
    @FocusState var clickedTextField: Field?
    
    @State private var viewModel = MapViewModel()
    
    /// penghubung antara Map dan MapCompass
    @Namespace private var mapScope
    
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
        guard let heading = viewModel.locationManager.heading, heading.headingAccuracy >= 0 else { return nil }
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
        .buttonStyle(.plain)
        .padding(.bottom, 20)
        .padding(.leading, 10)
    }
    
    // Tombol Compass untuk mengembalikan arah ke utara
    private var compassButton: some View {
        MapCompass(scope: mapScope)
            .mapControlVisibility(.visible)
            .padding(.leading, 28)
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Map(position: $viewModel.userCurrentPosition, scope: mapScope) {
                    if let userCoordinate = viewModel.locationManager.userLocation?.coordinate {
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
                    
                    routeCalloutAnnotations
                }
                .ignoresSafeArea()
                
                .mapControls{}
                
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
                                await viewModel.calculateShadedRoute(to: destinationCoordinate)
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
                    VStack {
                        // Menampilkan matahari sesuai jam
                        SunPositionView(screenWidth: geo.size.width)
                    }
                }
                
                .overlay(alignment: .top) {
                    WeatherAndUVIndexView(
                        viewModel: viewModel
                    )
                    .padding(.top, 60)
                    .padding(.leading, 20)
                }
                
                VStack {
                    HStack {
                        compassButton
                            .padding(.bottom, 5)
                        Spacer()
                    }
                    HStack {
                        recenterButton
                            .padding(.leading, 20)
                            .padding(
                                .bottom,
                                directionsSheetState != .hidden
                                ? collapsedSheetHeight + 16
                                : geo.size.height * 0.1 + 16
                            )
                        
                        Spacer()
                        
                        Text("🌡️ **\(viewModel.feelsLike)°**")
                            .padding(5)
                            .background(.regularMaterial, in: .capsule)
                            .padding(.trailing, 30)
                            .padding(
                                .bottom,
                                directionsSheetState != .hidden
                                ? collapsedSheetHeight + 16
                                : geo.size.height * 0.1 + 26
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
                                        viewModel.nativeRoutes = []
                                        viewModel.shadedRoutes = []
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
            
            // untuk membuat ID maps agar terbaca oleh compass
            .mapScope(mapScope)
            
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $navigateDestination) { destination in
            NavigateView(
                locationManager: viewModel.locationManager,
                destination: destination.coordinate,
                destinationTitle: destination.title,
                selectedRouteKind: selectedRouteKind,
                onArrivalDismissed: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        directionsSheetState = .hidden
                        currentPresentationDetents = .fraction(0.1)
                        clickedTextField = nil
                        showBottomPanelSheet = true
                        resolvedDestination = nil
                        resolvedOrigin = nil
                        editingField = .destination
                        viewModel.nativeRoutes = []
                        viewModel.shadedRoutes = []
                        viewModel.userDestinationText = ""
                    }
                }
            )
        }
    }
    
    //    @MapContentBuilder
    //    private var routeOverlay: some MapContent {
    //        if let route = viewModel.nativeRoutes.first {
    //            MapPolyline(route.polyline)
    //                .stroke(.yellow,
    //                        lineWidth: selectedRouteKind == "fastest" ? 6 : 2)
    //        }
    //
    //        ForEach(shadedRouteSegments, id: \.segment.id) { item in
    //            let polyline = MapPolyline(coordinates: item.segment.coordinate)
    //            let strokeWidth: CGFloat = selectedRouteKind == item.kind ? 6 : 2
    //            polyline.stroke(item.segment.color, lineWidth: strokeWidth)
    //        }
    //    }
    
    @MapContentBuilder
    private var routeOverlay: some MapContent {
        if let route = viewModel.nativeRoutes.first, selectedRouteKind != "fastest" {
            MapPolyline(route.polyline)
                .stroke(Color(.systemGray), lineWidth: 3)
        }
        
        ForEach(shadedRouteSegments.filter { $0.kind != selectedRouteKind }, id: \.segment.id) { item in
            MapPolyline(coordinates: item.segment.coordinate)
                .stroke(Color(.systemGray), lineWidth: 3)
        }
        
        if let route = viewModel.nativeRoutes.first, selectedRouteKind == "fastest" {
            MapPolyline(route.polyline)
                .stroke(.yellow, lineWidth: 6)
        }
        
        ForEach(shadedRouteSegments.filter { $0.kind == selectedRouteKind }, id: \.segment.id) { item in
            MapPolyline(coordinates: item.segment.coordinate)
                .stroke(item.segment.color, lineWidth: 6)
        }
    }
    
    @MapContentBuilder
    private var routeCalloutAnnotations: some MapContent {
        ForEach(orderedRouteOptions, id: \.kind) { option in
            if let coordinate = viewModel.midpointCoordinate(for: option.kind) {
                Annotation("", coordinate: coordinate, anchor: .top) {
                    RouteCalloutBubble(option: option, isSelected: option.kind == selectedRouteKind)
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
    
    /// Flatten semua shaded route jadi satu list segment + kind-nya, dengan rute yang
    /// lagi dipilih ditaruh paling akhir supaya digambar di atas (nggak ketutupan rute lain).
    private var shadedRouteSegments: [(kind: String, segment: RouteSegment)] {
        let all = viewModel.shadedRoutes.enumerated().flatMap { index, route -> [(kind: String, segment: RouteSegment)] in
            guard !route.coordinates.isEmpty else { return [] }
            let kind = index == 0 ? "shaded" : "shaded\(index + 1)"
            return route.segments.map { (kind, $0) }
        }
        return all.sorted { ($0.kind == selectedRouteKind ? 1 : 0) < ($1.kind == selectedRouteKind ? 1 : 0) }
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
        VStack(alignment: .leading, spacing: 3) {
            Text(option.kind == "fastest" ? "Standard" : option.title)
                .font(.system(size: 18, weight: .bold))
            
            //            Text(option.subtitle)
            //                .font(.system(size: 12))
            //                .opacity(0.85)
            //                .lineLimit(2)
        }
        .frame(width: 150)
        .foregroundStyle(.white)
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
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
