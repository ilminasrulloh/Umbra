//
//  ArrivalSummarySheet.swift
//  Umbra
//
//  Created by Caroline Ang on 09/07/26.
//

import SwiftUI

struct ArrivalSummarySheet: View {
    let info: ArrivalInfo
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 36, height: 36)
                    Image(systemName: "mappin")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                Text(info.destinationTitle)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: onDismiss) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 36, height: 36)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            
            Text("😎")
                .font(.system(size: 56))
            
            arrivalMessage
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(.label))
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }
    
    private var arrivalMessage: Text {
        let minutes = info.minutesOfSunAvoided
        let unit = minutes == 1 ? "minute" : "minutes"
        return Text("You're here! That's " + "\(minutes) \(unit) of sun").fontWeight(.bold)
        + Text(" you didn't have to deal with.")
    }
}
