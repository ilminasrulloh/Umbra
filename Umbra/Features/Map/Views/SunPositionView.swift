//
//  SunPositionView.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 12/07/26.
//

import SwiftUI
import Combine


struct SunPositionView: View {
    
    // MARK: - Konfigurasi
    // Semua properti di bawah punya nilai default, jadi saat dipanggil dari
    // MapView cukup isi `screenWidth` saja — sisanya boleh dikosongkan.
    
    /// Lebar area/layar yang tersedia. Dipakai untuk menghitung seberapa jauh
    /// matahari boleh bergeser ke kanan (wajib diisi, tidak ada default,
    /// karena setiap layar device beda-beda lebarnya).
    let screenWidth: CGFloat
    
    /// Jam mulai matahari bergerak. Default: jam 10 pagi.
    var startHour: Int = 10
    
    /// Jam matahari berhenti bergerak (sudah sampai ujung kanan). Default: jam 2 siang.
    var endHour: Int = 14
    
    /// Lebar gambar matahari.
    var imageWidth: CGFloat = 300
    
    /// Nama asset gambar matahari di Assets.xcassets.
    var imageName: String = "sun-image"
    
    /// Waktu "sekarang" yang disimpan di state, supaya body bisa re-render
    /// tiap kali waktunya berubah (di-update oleh sunTimer di bawah).
    @State private var currentTime: Date = Date()
    
    /// Timer yang "membangunkan" view setiap 60 detik, supaya posisi
    /// matahari ikut ter-update mendekati real-time.
    private let sunTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // MARK: - Body
    
    var body: some View {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: imageWidth)
            .offset(x: xOffset)
            // Animasi halus supaya perpindahannya nggak "loncat" tiba-tiba
            .animation(.easeInOut(duration: 1), value: sunProgress)
            // Setiap sunTimer "berbunyi" (tiap 60 detik), update currentTime.
            .onReceive(sunTimer) { newTime in
                currentTime = newTime
            }
    }
    
    // MARK: - Logika perhitungan posisi
    
    /// Progress posisi matahari, dari 0.0 (jam `startHour`) sampai 1.0 (jam `endHour`).
    /// - Sebelum `startHour` -> 0.0 (matahari nempel di kiri)
    /// - Setelah `endHour` -> 1.0 (matahari nempel di kanan)
    /// - Di antaranya -> dihitung proporsional sesuai jam berjalan
    private var sunProgress: CGFloat {
        let calendar = Calendar.current
        
        guard
            let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: currentTime),
            let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: currentTime)
        else { return 0 }
        
        if currentTime <= start { return 0 }
        if currentTime >= end { return 1 }
        
        let totalDuration = end.timeIntervalSince(start)   // total detik dari startHour ke endHour
        let elapsed = currentTime.timeIntervalSince(start) // detik yang sudah berlalu sejak startHour
        return CGFloat(elapsed / totalDuration)
    }
    
    /// Jarak geser horizontal (dalam point), hasil dari sunProgress dikali
    /// jarak maksimum yang boleh ditempuh matahari.
    private var xOffset: CGFloat {
        let maxOffset = max(screenWidth - imageWidth, 0)
        return sunProgress * maxOffset
    }
}

#Preview {
    GeometryReader { geo in
        SunPositionView(screenWidth: geo.size.width)
    }
    .background(Color.blue.opacity(0.15))
}

