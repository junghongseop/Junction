//
//  RouteSummaryCard.swift
//  DriveInGyeongbuk
//
//  Figma "iPhone 17 - 4"의 하단 경로 요약 카드.
//

import SwiftUI

struct RouteSummaryCard: View {
    let destination: NaverLocation
    let route: DrivingRoute
    let safeRoute: DrivingRoute?
    let onStart: () -> Void

    private static let primaryText = Color(red: 218 / 255, green: 226 / 255, blue: 253 / 255)
    private static let accentText = Color(red: 179 / 255, green: 197 / 255, blue: 1)
    private static let green = Color(red: 0, green: 230 / 255, blue: 118 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(destination.title)
                .font(.callout)
                .foregroundStyle(Self.primaryText)
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline) {
                distanceLabel
                Spacer()
                Text(route.tollFare, format: .currency(code: "KRW").precision(.fractionLength(0)))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 11) {
                metricCard(title: route.tollFare > 0 ? "Hi-Pass Pref." : "Fastest",
                           minutes: route.durationMinutes,
                           color: Self.green)
                metricCard(title: "Safe Path",
                           minutes: (safeRoute ?? route).durationMinutes,
                           color: Self.accentText)
            }

            Button(action: onStart) {
                Label("Start Drive", systemImage: "location.north.fill")
                    .font(.body.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Color(red: 0, green: 82 / 255, blue: 212 / 255))
        }
        .routeCardStyle()
    }

    private var distanceLabel: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(route.distanceValue)
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(Self.accentText)
            Text(route.distanceUnit)
                .font(.callout.weight(.bold))
                .foregroundStyle(Self.accentText.opacity(0.7))
        }
    }

    private func metricCard(title: String, minutes: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(0.6)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(minutes, format: .number)
                    .font(.system(size: 40, weight: .heavy))
                Text("min")
                    .font(.callout.weight(.bold))
            }
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(height: 107)
        .background(Color(red: 34 / 255, green: 42 / 255, blue: 61 / 255),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.55)))
    }
}

private extension DrivingRoute {
    var durationMinutes: Int { max(1, Int(ceil(Double(duration) / 60))) }
    var distanceValue: String {
        distance >= 1000 ? String(format: "%.1f", Double(distance) / 1000) : "\(distance)"
    }
    var distanceUnit: String { distance >= 1000 ? "km" : "m" }
}

extension View {
    func routeCardStyle() -> some View {
        self
            .padding(20)
            .background(Color(red: 19 / 255, green: 31 / 255, blue: 61 / 255).opacity(0.97),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.25), radius: 15, y: 10)
    }
}
