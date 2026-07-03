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
    @StateObject private var locationManager = UserLocationManager()
    @State private var userCurrentPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    
    var body: some View {
        
        ZStack (alignment: .top) {
            
            Map(position: $userCurrentPosition) {
                UserAnnotation()
            }
            .ignoresSafeArea()
            .onAppear {
                locationManager.RequestUserLocation()
            }
            
            VStack {
                
                HStack(spacing: 16) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.system(size: 48))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("65 m")
                            .font(.headline)
                            .foregroundColor(.black)
                        
                        Text("Turn left onto the path")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                .frame(width: 340)
                .padding(16)
                .background(Color.white.opacity(0.90))
                .cornerRadius(24)
                
                Spacer()
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("7 mins")
                            .font(.headline)
                            .foregroundColor(.black)
                        
                        Text("9:50 AM . 700 m")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                .frame(width: 340)
                .padding(16)
                .background(Color.white.opacity(0.90))
                .cornerRadius(24)
            }
        }
    }
}

#Preview {
    NavigateView()
}
