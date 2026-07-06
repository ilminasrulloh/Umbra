//
//  UserLocationIndicator.swift
//  Umbra
//
//  Created by M Ilmi Nasrulloh on 06/07/26.
//

import SwiftUI

struct UserLocationIndicator: View {
    var headingDegrees: Double?

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Lingkaran pancaran cahaya yang berdenyut
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.35), Color.blue.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 45
                    )
                )
                .frame(width: 90, height: 90)
                .scaleEffect(isPulsing ? 1.25 : 0.75)
                .opacity(isPulsing ? 0.0 : 0.9)
                .animation(
                    .easeOut(duration: 1.8).repeatForever(autoreverses: false),
                    value: isPulsing
                )

            // Beam arah hadap (cone), hanya muncul kalau heading valid
            if let headingDegrees {
                HeadingCone()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.6), Color.blue.opacity(0)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 56, height: 56)
                    //.offset(y: -18)
                    .rotationEffect(.degrees(headingDegrees), anchor: .bottom)
                    .offset(y: -27)
                    .animation(.easeInOut(duration: 0.25), value: headingDegrees)
            }

            // Border putih
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

            // Titik biru di tengah
            Circle()
                .fill(Color.blue)
                .frame(width: 16, height: 16)
        }
        .onAppear { isPulsing = true }
    }
}

/// Bentuk kerucut/fan sederhana untuk beam arah hadap, menghadap ke atas (utara) secara default.
private struct HeadingCone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bottomCenter = CGPoint(x: rect.midX, y: rect.maxY)
        let topLeft = CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY)

        path.move(to: bottomCenter)
        path.addLine(to: topLeft)
        path.addQuadCurve(
            to: topRight,
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.35)
        )
        path.addLine(to: bottomCenter)
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
        UserLocationIndicator(headingDegrees: 45)
    }
}
