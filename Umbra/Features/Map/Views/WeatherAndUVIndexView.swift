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
    @State var currentButtonView: String = "weather"
    
    private let states = ["weather", "details", "guidance"]
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Group {
            if currentButtonView == "weather" {
                Text(viewModel.weatherText)
                    .padding(20)
                    .glassEffect()
            } else if currentButtonView == "details" {
                VStack(alignment: .leading, spacing: 5) {
                    Text("🌡️ Feels Like **\(viewModel.feelsLike)°**")
                    Text("☀️ UV Index: **\(viewModel.uvIndex) (\(viewModel.uvIndexText))**")
                    HStack {
                        Image(systemName: viewModel.weatherEmoji)
                        Text(LocalizedStringKey(viewModel.weatherSuggestion))
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(20)
                .glassEffect()
            } else {
                HStack {
                    Text("\(viewModel.itemReminderEmoji)")
                    Text(LocalizedStringKey(viewModel.itemReminderText))
                }
                .padding(20)
                .glassEffect()
            }
        }
        .animation(.easeInOut, value: currentButtonView)
        .onReceive(timer) { _ in
            advanceState()
        }
    }
    
    private func advanceState() {
        guard let currentIndex = states.firstIndex(of: currentButtonView) else { return }
        let nextIndex = (currentIndex + 1) % states.count
        currentButtonView = states[nextIndex]
    }
}


#Preview {
    WeatherAndUVIndexView(viewModel: MapViewModel())
}
