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
    
    /// Lebar area/layar yang tersedia. Dipakai untuk menghitung seberapa jauh
    /// matahari boleh bergeser ke kanan (wajib diisi, tidak ada default,
    /// karena setiap layar device beda-beda lebarnya).
    let screenWidth: CGFloat
    
    /// Jam mulai matahari bergerak
    var startHour: Int = 06
    
    /// Jam matahari berhenti bergerak (sudah sampai ujung kanan)
    var endHour: Int = 18
    
    /// Lebar gambar matahari.
    var imageWidth: CGFloat = 300
    
    /// Offset vertikal (dalam point) untuk menggeser posisi matahari naik/turun.
    var verticalOffset: CGFloat = -100
    
    /// Seberapa banyak bagian matahari (dalam point) yang tetap kelihatan di tepi
    /// layar saat posisi ekstrem — sebelum `startHour` dan setelah `endHour`
    /// Semakin kecil angkanya, semakin "ngumpet" mataharinya di ujung layar.
    var edgePeekWidth: CGFloat = 100
    
    /// Nama asset gambar matahari di Assets.xcassets.
    var imageName: String = "sun-center"
    
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
            .offset(x: xOffset, y: verticalOffset)
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
    
    /// Jarak geser horizontal (dalam point)
    private var xOffset: CGFloat {
        // posisi "terbit": nongol dikit dari kiri
        let startX = -imageWidth + edgePeekWidth
        
        // posisi "terbenam": nongol dikit dari kanan
        let endX = screenWidth - edgePeekWidth
        
        let travelDistance = endX - startX
        return startX + (sunProgress * travelDistance)
    }
}

#Preview {
    GeometryReader { geo in
        SunPositionView(screenWidth: geo.size.width)
    }
    .background(Color.blue.opacity(0.15))
}

