//
//  WeatherAndUVIndexView.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI
import Combine
struct WeatherAndUVIndexView: View {
    @Bindable var viewModel: MapViewModel
    
    @State private var expandWeatherUVView = false
    @State private var currentPage = 0
    
    var body: some View {
        VStack(alignment: .center) {
                HStack {
                    Text(viewModel.weatherText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.leading, 40)
                        .padding(.trailing, 20)
                        .padding(.vertical, 10)
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            expandWeatherUVView.toggle()
                        }
                    }){
                        Image(systemName: expandWeatherUVView ? "chevron.up" : "chevron.down")
                            .font(.title3)
                            .padding(20)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(25)
                    }
                }
                .frame(width: 350)
                .background(Color(.systemBackground))
                .cornerRadius(25)
                
                if expandWeatherUVView {
                    VStack(spacing: 0) {
                        HStack{
                            Text("🌡️ Feels Like **\(viewModel.feelsLike)°**")
                                .padding(.leading, 10)
                            
                            Spacer()
                            
                            Text("☀️ UV Index: **\(viewModel.uvIndex) (\(viewModel.uvIndexText))**").padding(.trailing, 10)
                        }
                        .font(.subheadline)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemBackground))
                        
                        TabView(selection: $currentPage) {
                            WeatherCard(text: viewModel.weatherSuggestion)
                                .tag(0)
                            WeatherCard(text: viewModel.itemReminderText)
                                .tag(1)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 100)
                        
                        WeatherNavigationDots(currentPage: $currentPage)
                            .background(Color(.secondarySystemBackground))
                    }
                    
                    .frame(width: 350)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.9, anchor: .top).combined(with: .opacity)
                    ))
                }
                
            }
        }
    }


private struct WeatherCard: View {
    let text: String
    
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.callout)
            .foregroundStyle(Color(.secondaryLabel))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(15)
            .frame(maxHeight: .infinity, alignment: .center)
            .background(Color(.secondarySystemBackground))
    }
}

private struct WeatherNavigationDots: View {
    @Binding var currentPage: Int
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<2) { index in
                Circle()
                    .fill(index == currentPage ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .onTapGesture {
                        withAnimation {
                            currentPage = index
                        }
                    }
                    .contentShape(Circle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

#Preview {
    WeatherAndUVIndexView(viewModel: MapViewModel())
}
