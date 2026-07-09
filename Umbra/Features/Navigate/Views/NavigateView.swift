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
    let locationManager: LocationManager
    var selectedRouteKind: String
    
    @State private var viewModel = NavigateViewModel()
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDestination: CLLocationCoordinate2D?
    @State private var selectedStepIndex: Int = 0
    @State private var hasAutoStarted = false
    
    @State private var showDetailsSheet = false
    @State private var startAddressText: String = "My Location"
    @State private var destinationAddressText: String = ""
    /// Tujuan yang dikirim dari MapView (hasil pencarian user)
    let initialDestination: CLLocationCoordinate2D
    let destinationTitle: String
    
    /// Kontrol tampil/tidaknya bottom sheet "kamu sudah sampai". Muncul begitu
    /// `viewModel.didArrive` jadi true. Sekarang bisa ditutup lewat tombol checkmark
    /// ATAU swipe-down — keduanya sama-sama memicu `.sheet(onDismiss:)` di bawah,
    /// yang menutup NavigateView dan kembali ke MapView.
    @State private var showArrivalSheet = false
    
    /// Dipanggil sesaat sebelum NavigateView menutup diri (baik lewat tap checkmark
    /// maupun swipe-down di ArrivalSummarySheet). MapView bisa pakai closure ini untuk
    /// membersihkan tampilan rute yang sempat digambar sebelumnya (destinasi terpilih,
    /// polyline hasil kalkulasi, dsb), supaya begitu kembali ke MapView cuma lokasi
    /// user terkini yang tampil — tidak ada sisa rute lama.
    var onArrivalDismissed: (() -> Void)? = nil
    
    init(
        locationManager: LocationManager,
        destination: CLLocationCoordinate2D,
        destinationTitle: String = "Tujuan",
        selectedRouteKind: String = "shaded",
        onArrivalDismissed: (() -> Void)? = nil
    ) {
        self.locationManager = locationManager
        self.initialDestination = destination
        self.destinationTitle = destinationTitle
        self.selectedRouteKind = selectedRouteKind
        self.onArrivalDismissed = onArrivalDismissed
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            navigateMapView
            
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
            
            // MARK: Area bawah — panel "menyiapkan navigasi" (idle) atau summary card (saat navigasi)
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
                            dismiss()
                        },
                        onShowDetails: {
                            loadAddressesIfNeeded()
                            showDetailsSheet = true
                        }
                    )
                } else {
                    startNavigationPanel
                }
            }
        }
        .onAppear {
            locationManager.requestUserLocation()
            attemptAutoStartNavigation()
        }
        .onChange(of: viewModel.isNavigating) { _, isNavigating in
            if isNavigating {
                selectedStepIndex = 0
            }
        }
        .onChange(of: viewModel.currentStepIndex) { _, newValue in
            selectedStepIndex = newValue
        }
        .onChange(of: selectedStepIndex) { _, newIndex in
            handleCarouselStepChange(newIndex)
        }
        .onChange(of: locationManager.userLocation) { _, _ in
            attemptAutoStartNavigation()
        }
        .onChange(of: locationManager.userLocation?.timestamp) { _, _ in
            guard viewModel.isNavigating, let newLocation = locationManager.userLocation else { return }
            
            viewModel.updateProgress(userLocation: newLocation)
            // `updateProgress` bisa saja baru mendeteksi kedatangan dan menghentikan
            // navigasi (isNavigating -> false) — kalau begitu, hentikan di sini supaya
            // tidak menggerakkan kamera / mengecek off-route untuk navigasi yang sudah berakhir.
            guard viewModel.isNavigating else { return }
            viewModel.setCameraTarget(
                coordinate: newLocation.coordinate,
                heading: effectiveNavigationHeading(location: newLocation)
            )
            
            if viewModel.isOffRoute(newLocation) {
                Task {
                    await viewModel.calculateRoute(from: newLocation.coordinate, to: currentDestination, kind: viewModel.selectedKind)
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
        // Sinyal "sudah sampai" dari ViewModel — tampilkan bottom sheet kedatangan
        // DI ATAS layar navigasi ini. NavigateView baru benar-benar menutup diri
        // (kembali ke MapView) setelah user menekan tombol checkmark di sheet.
        .onChange(of: viewModel.didArrive) { _, arrived in
            guard arrived else { return }
            showArrivalSheet = true
        }
        .sheet(isPresented: $showArrivalSheet, onDismiss: {
            // Titik ini jalan untuk KEDUA jalur: tap checkmark (yang cuma set
            // showArrivalSheet = false) maupun swipe-down manual oleh user.
            onArrivalDismissed?()
            dismiss()
        }) {
            ArrivalSummarySheet(
                info: ArrivalInfo(
                    destinationTitle: destinationTitle,
                    minutesOfSunAvoided: viewModel.minutesOfSunAvoided ?? 0
                ),
                onDismiss: {
                    showArrivalSheet = false
                }
            )
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDetailsSheet) {
            RouteDetailsSheet(
                startAddress: startAddressText,
                destinationAddress: destinationAddressText.isEmpty ? destinationTitle : destinationAddressText,
                steps: viewModel.activeSteps,
                onDismiss: { showDetailsSheet = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
    var navigateMapView: some View {
        MapReader { proxy in
            Map(position: $viewModel.camera) {
                userAnnotation
                
                if let shaded = viewModel.shadedRouteResult, !shaded.coordinates.isEmpty {
                    MapPolyline(coordinates: shaded.coordinates)
                        .stroke(.blue, lineWidth: 6)
                }
                
                destinationMarker
            }
            .mapControls {
                MapCompass()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in viewModel.pauseFollowingCamera() }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { _ in viewModel.pauseFollowingCamera() }
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    @MapContentBuilder
    var userAnnotation: some MapContent {
        if let userCoordinate = locationManager.userLocation?.coordinate {
            Annotation("", coordinate: userCoordinate) {
                UserLocationIndicator(headingDegrees: coneRotationDegrees)
            }
            .annotationTitles(.hidden)
        }
    }
    
    @MapContentBuilder
    var destinationMarker: some MapContent {
        Marker(destinationTitle, coordinate: currentDestination)
            .tint(.red)
    }
    
    
    // MARK: - Carousel <-> Map sync
    
    /// Dipanggil tiap `selectedStepIndex` berubah — baik karena user menggeser
    /// `InstructionCarouselCard` secara manual, MAUPUN karena `currentStepIndex`
    /// (progress GPS) menyamakannya balik lewat onChange di atas. Kalau step yang
    /// ditampilkan carousel bukan step yang sedang aktif, kamera "meninjau" lokasi
    /// step tsb. Begitu carousel kembali ke step aktif, kamera kembali mengikuti
    /// posisi user secara live.
    private func handleCarouselStepChange(_ index: Int) {
        guard viewModel.isNavigating else { return }
        let steps = viewModel.activeSteps
        guard steps.indices.contains(index) else { return }
        
        if index == viewModel.currentStepIndex {
            viewModel.resumeFollowingCamera()
        } else {
            viewModel.previewStep(at: steps[index].coordinate)
        }
    }
    
    // MARK: - Auto-start navigasi
    
    /// Coba mulai navigasi begitu lokasi user tersedia — menggantikan tombol
    /// "Mulai Navigasi" yang dulu ada di `startNavigationPanel`.
    private func attemptAutoStartNavigation() {
        // Sudah pernah dimulai, atau memang sedang navigasi -> tidak perlu apa-apa lagi.
        guard !hasAutoStarted, !viewModel.isNavigating else { return }
        // GPS belum dapat fix -> keluar dulu, nanti dicoba lagi lewat onChange di atas.
        guard let origin = locationManager.userLocation?.coordinate else { return }
        
        hasAutoStarted = true
        Task {
            await viewModel.startNavigation(from: origin, to: currentDestination, kind: selectedRouteKind)
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
    
    private var currentDestination: CLLocationCoordinate2D {
        selectedDestination ?? initialDestination
    }
    
    // MARK: - Panel "Menyiapkan Navigasi" (ditampilkan sebentar sebelum navigasi otomatis dimulai)
    
    /// Dulu berisi tombol "Mulai Navigasi". Sekarang navigasi dimulai otomatis
    /// lewat `attemptAutoStartNavigation()`, jadi panel ini murni indikator
    /// bahwa app sedang menunggu GPS/menghitung rute — biasanya cuma tampil sebentar.
    private var startNavigationPanel: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Menyiapkan navigasi ke \(destinationTitle)...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
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
    
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .padding(10)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 3)
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
    private var topOverlayArea: some View {
        VStack(spacing: 8) {
            HStack {
                //closeButton
                Spacer()
            }
            .padding(.horizontal)
            
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

    /// Hanya jalan sekali per sesi navigasi — kalau alamat tujuan sudah pernah
    /// berhasil di-resolve, tidak perlu geocode ulang tiap kali "Details" ditekan.
    private func loadAddressesIfNeeded() {
        guard destinationAddressText.isEmpty else { return }
        Task {
            if let userLocation = locationManager.userLocation {
                startAddressText = await reverseGeocodeAddress(for: userLocation) ?? "My Location"
            }
            let destLocation = CLLocation(
                latitude: currentDestination.latitude,
                longitude: currentDestination.longitude
            )
            destinationAddressText = await reverseGeocodeAddress(for: destLocation) ?? destinationTitle
        }
    }

    private func reverseGeocodeAddress(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return formattedAddress(from: placemark)
        } catch {
            return nil
        }
    }

    private func formattedAddress(from placemark: CLPlacemark) -> String {
        var components: [String] = []

        if let thoroughfare = placemark.thoroughfare {
            var street = thoroughfare
            if let subThoroughfare = placemark.subThoroughfare {
                street += " No. \(subThoroughfare)"
            }
            components.append(street)
        } else if let name = placemark.name {
            components.append(name)
        }

        if let locality = placemark.locality {
            components.append(locality)
        }

        var stateZip = ""
        if let area = placemark.administrativeArea { stateZip += area }
        if let zip = placemark.postalCode {
            stateZip += stateZip.isEmpty ? zip : " \(zip)"
        }
        if !stateZip.isEmpty { components.append(stateZip) }

        if let country = placemark.country {
            components.append(country)
        }

        return components.joined(separator: ", ")
    }
}

#Preview {
    NavigateView(
        locationManager: LocationManager(),
        destination: CLLocationCoordinate2D(latitude: -6.1754, longitude: 106.8272),
        destinationTitle: "Monas"
    )
}

