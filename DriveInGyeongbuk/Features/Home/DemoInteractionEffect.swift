//
//  DemoInteractionEffect.swift
//  DriveInGyeongbuk
//
//  자동 시연에서 앱이 어떤 컨트롤을 조작하는지 관객에게 보여 주는 터치 효과.
//

import SwiftUI

enum DemoInteractionLabelPosition {
    case above
    case below
}

struct DemoInteractionEffect: View {
    let label: String
    var systemImage = "hand.tap.fill"
    var labelPosition: DemoInteractionLabelPosition = .above

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 42, height: 42)
                .scaleEffect(isPulsing ? 1.8 : 0.75)
                .opacity(isPulsing ? 0 : 0.9)

            Circle()
                .fill(Color(red: 79 / 255, green: 121 / 255, blue: 1).opacity(0.92))
                .frame(width: 42, height: 42)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)

            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: labelPosition == .above ? .bottom : .top) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color(red: 11 / 255, green: 19 / 255, blue: 38 / 255).opacity(0.94),
                            in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.3)))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .fixedSize()
                .offset(y: labelPosition == .above ? -54 : 54)
        }
        .transition(.scale(scale: 0.7).combined(with: .opacity))
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

extension View {
    @ViewBuilder
    func demoInteraction(_ label: String,
                         isActive: Bool,
                         systemImage: String = "hand.tap.fill",
                         labelPosition: DemoInteractionLabelPosition = .above) -> some View {
        overlay {
            if isActive {
                DemoInteractionEffect(label: label,
                                      systemImage: systemImage,
                                      labelPosition: labelPosition)
            }
        }
    }
}
