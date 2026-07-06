//
//  NavigateView.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 01/07/26.
//

import SwiftUI
import Combine
import MapKit

struct NavigateView: View {
    @State private var locationManager = LocationManager()
    @State private var viewModel = NavigateViewModel()

    @State private var selectedDestination: CLLocationCoordinate2D?
    /// Index instruksi yang sedang ditampilkan di carousel (bisa berbeda dari
    /// `viewModel.currentStepIndex` kalau user lagi swipe untuk preview instruksi lain)
    @State private var selectedStepIndex: Int = 0

    /// Tujuan demo default: Monas, Jakarta.
    /// Ganti sesuai lokasi yang kamu pakai untuk testing.
    private let demoDestination = CLLocationCoordinate2D(latitude: -6.3028, longitude: 106.6520)
    
    var body: some View {
        ZStack(alignment: .top) {
            MapReader { proxy in
                Map(position: $viewModel.camera) {
                    if let userCoordinate = locationManager.userLocation?.coordinate {
                        Annotation("", coordinate: userCoordinate) {
                            UserLocationIndicator(headingDegrees: coneRotationDegrees)
                        }
                        .annotationTitles(.hidden)
                    }

                    if let route = viewModel.route {
                        MapPolyline(route.polyline)
                            .stroke(.blue, lineWidth: 6)
                    }

                    if let destination = currentDestination {
                        Marker("Tujuan", coordinate: destination)
                            .tint(.red)
                    }
                }
                .mapControls {
                    MapCompass()
                }
                .onTapGesture { screenPoint in
                    guard !viewModel.isNavigating else { return }
                    if let coordinate = proxy.convert(screenPoint, from: .local) {
                        selectedDestination = coordinate
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            // MARK: Area atas — status banner (idle/error) atau instruction carousel (saat navigasi)
            topOverlayArea
                .padding(.top, 8)

            // MARK: Tombol recenter — kiri bawah, tepat di atas card bawah
            VStack {
                Spacer()
                HStack {
                    recenterButton
                        .padding(.leading, 16)
                    Spacer()
                }
            }
            .padding(.bottom, 130)

            // MARK: Area bawah — panel mulai navigasi (idle) atau summary card (saat navigasi)
            VStack {
                Spacer()
                if viewModel.isNavigating {
                    NavigationSummaryCard(
                        etaMinutesText: etaMinutesText,
                        arrivalTimeText: arrivalTimeText,
                        remainingDistanceText: remainingDistanceText,
                        onEndRoute: {
                            viewModel.stopNavigation()
                            selectedDestination = nil
                        }
                    )
                } else {
                    startNavigationPanel
                }
            }
        }
        .onAppear {
            locationManager.RequestUserLocation()
        }
        .onChange(of: viewModel.isNavigating) { _, isNavigating in
            if isNavigating {
                selectedStepIndex = 0
            }
        }
        .onChange(of: viewModel.currentStepIndex) { _, newValue in
            selectedStepIndex = newValue
        }
        // @Observable tidak punya publisher Combine ($properti) seperti @Published dulu.
        // Solusinya: pantau `timestamp`-nya — nilai ini SELALU berubah tiap ada data baru
        // dari GPS/kompas, jadi bisa dipakai sebagai "sinyal" kapan harus jalankan side effect.
        .onChange(of: locationManager.userLocation?.timestamp) { _, _ in
            guard viewModel.isNavigating, let newLocation = locationManager.userLocation else { return }

            viewModel.updateProgress(userLocation: newLocation)
            viewModel.setCameraTarget(
                coordinate: newLocation.coordinate,
                heading: effectiveNavigationHeading(location: newLocation)
            )

            if viewModel.isOffRoute(newLocation) {
                Task {
                    await viewModel.calculateRoute(from: newLocation.coordinate, to: currentDestination ?? demoDestination)
                }
            }
        }
        .onChange(of: locationManager.heading?.timestamp) { _, _ in
            guard viewModel.isNavigating, let currentLocation = locationManager.userLocation else { return }
            viewModel.setCameraTarget(
                coordinate: currentLocation.coordinate,
                heading: effectiveNavigationHeading(location: currentLocation)
            )
        }
    }

    // MARK: - Heading helpers

    private func effectiveNavigationHeading(location: CLLocation) -> CLLocationDirection {
        if let heading = locationManager.heading, heading.headingAccuracy >= 0 {
            return heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        }
        return location.course >= 0 ? location.course : 0
    }

    private var coneRotationDegrees: Double? {
        guard let heading = locationManager.heading, heading.headingAccuracy >= 0 else { return nil }
        let value = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        return viewModel.isNavigating ? 0 : value
    }

    private var recenterButton: some View {
        Button {
            guard let location = locationManager.userLocation else { return }
            viewModel.recenterCamera(
                to: location.coordinate,
                heading: effectiveNavigationHeading(location: location)
            )
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .padding(12)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 3)
        }
    }

    // MARK: - ETA formatting

    private var etaMinutesText: String {
        "\(max(1, Int(viewModel.remainingTravelTime / 60)))"
    }

    private var arrivalTimeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: viewModel.estimatedArrivalDate)
    }

    private var remainingDistanceText: String {
        let meters = viewModel.remainingDistance
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }

    // MARK: - Top overlay (dipecah jadi beberapa computed property kecil
    // supaya type-checker tidak menganalisis semuanya sebagai satu expression raksasa)

    @ViewBuilder
    private var topOverlayArea: some View {
        VStack(spacing: 8) {
            permissionAndErrorBanners
            instructionCarousel
        }
    }

    @ViewBuilder
    private var permissionAndErrorBanners: some View {
        if let error = viewModel.errorMessage {
            statusBanner(text: error, color: .red)
        }

        if let locationError = locationManager.lastErrorMessage {
            statusBanner(text: locationError, color: .orange)
            openSettingsButton
        } else if locationManager.userAuthorizationStatus == .notDetermined {
            statusBanner(text: "Menunggu izin lokasi...", color: .blue)
        } else if locationManager.userLocation == nil {
            statusBanner(text: "Mencari sinyal GPS...", color: .blue)
        }
    }

    private var openSettingsButton: some View {
        Button("Buka Pengaturan") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        .font(.footnote)
    }

    @ViewBuilder
    private var instructionCarousel: some View {
        if viewModel.isNavigating, !viewModel.activeSteps.isEmpty {
            InstructionCarouselCard(
                steps: viewModel.activeSteps,
                selectedIndex: $selectedStepIndex,
                activeStepIndex: viewModel.currentStepIndex,
                liveDistanceToActiveStep: viewModel.distanceToNextStep
            )
        }
    }

    @ViewBuilder
    private func statusBanner(text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .padding(8)
            .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private var currentDestination: CLLocationCoordinate2D? {
        selectedDestination ?? (viewModel.isNavigating ? demoDestination : nil)
    }

    // MARK: - Panel "Mulai Navigasi" (ditampilkan sebelum navigasi dimulai)

    private var startNavigationPanel: some View {
        VStack(spacing: 12) {
            Button {
                guard let origin = locationManager.userLocation?.coordinate else { return }
                let destination = selectedDestination ?? demoDestination
                Task {
                    await viewModel.startNavigation(from: origin, to: destination)
                }
            } label: {
                Label(
                    selectedDestination == nil ? "Mulai Navigasi ke Monas (demo)" : "Mulai Navigasi",
                    systemImage: "location.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(locationManager.userLocation == nil)

            Text("Tap peta untuk memilih tujuan, atau langsung mulai untuk pakai tujuan demo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}

#Preview {
    ContentView()
}
