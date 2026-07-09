//
//  WeatherAndUVIndexView.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI

struct WeatherAndUVIndexView: View {
    @Bindable var viewModel: MapViewModel
    @Binding var expandUVIndexButton: Bool
    @Binding var expandWeatherButton: Bool
    
    var body: some View {
        HStack(alignment: .top) {
            Button(action: { expandWeatherButton.toggle() }) {
                if expandWeatherButton {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: viewModel.weatherSymbolName)
                                .padding(.trailing, 5)
                            Text(viewModel.temperature)
                        }
                        Text(viewModel.feelsLike)
                            .padding(.top, 2)
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.leading, 20)
                    .padding(.trailing, 30)
                    .background(.ultraThickMaterial)
                    .cornerRadius(20)
                    .padding(.leading, 20)
                    .padding(.trailing, 10)
                    
                } else {
                    HStack {
                        Image(systemName: viewModel.weatherSymbolName)
                            .padding(.trailing, 5)
                        Text(viewModel.temperature)
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 20)
                    .background(.ultraThickMaterial)
                    .cornerRadius(25)
                    .padding(.leading, 20)
                    .padding(.trailing, 10)
                }
            }
            
            Button(action: { expandUVIndexButton.toggle() }) {
                if expandUVIndexButton {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "sun.min")
                                .padding(.trailing, 5)
                            Text("\(viewModel.uvIndex)")
                        }
                        Text(viewModel.uvCategory)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Text("Use Sunscreen")
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.leading, 20)
                    .padding(.trailing, 30)
                    .background(.ultraThickMaterial)
                    .cornerRadius(20)
                    .padding(.leading, 10)
                    
                } else {
                    HStack {
                        Image(systemName: "sun.min")
                            .padding(.trailing, 5)
                        Text("\(viewModel.uvIndex)")
                    }
                    .fontWeight(.medium)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 20)
                    .background(.ultraThickMaterial)
                    .cornerRadius(25)
                    .padding(.leading, 10)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.top, 55)
    }
}
