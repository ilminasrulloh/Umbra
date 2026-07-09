////
////  LocationInputCard.swift
////  Umbra
////
////  Created by Davin P on 06/07/26.
////
//
//import SwiftUI
//
//struct LocationRow: View {
//    enum Kind {
//        case origin
//        case destination
//
//        var iconName: String {
//            switch self {
//            case .origin: return "location.fill"
//            case .destination: return "bag.fill"
//            }
//        }
//
//        var iconColor: Color {
//            switch self {
//            case .origin: return .blue
//            case .destination: return .orange
//            }
//        }
//    }
//
//    let kind: Kind
//    let title: String
//
//    var body: some View {
//        HStack(spacing: 12) {
//            ZStack {
//                Circle()
//                    .fill(kind.iconColor)
//                    .frame(width: 28, height: 28)
//                Image(systemName: kind.iconName)
//                    .font(.system(size: 13, weight: .semibold))
//                    .foregroundStyle(.white)
//            }
//
//            Text(title)
//                .font(.system(size: 16))
//                .foregroundStyle(.primary)
//
//            Spacer()
//
//            Image(systemName: "line.3.horizontal")
//                .foregroundStyle(.tertiary)
//                .font(.system(size: 15, weight: .semibold))
//        }
//        .padding(.vertical, 10)
//        .padding(.horizontal, 12)
//    }
//}
//
//struct LocationInputStack: View {
//    let originTitle: String
//    let destinationTitle: String
//
//    var body: some View {
//        ZStack(alignment: .leading) {
//            VStack(spacing: 0) {
//                LocationRow(kind: .origin, title: originTitle)
//                Divider().padding(.leading, 54)
//                LocationRow(kind: .destination, title: destinationTitle)
//            }
//        }
//        .background(Color(.secondarySystemBackground))
//        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
//    }
//}
//
//#Preview {
//    LocationInputStack(originTitle: "My Location", destinationTitle: "The Breeze")
//        .padding()
//}
