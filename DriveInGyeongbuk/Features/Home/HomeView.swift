//
//  HomeView.swift
//  DriveInGyeongbuk
//
//  Created by 정홍섭 on 8/22/26.
//

import SwiftUI

struct HomeView: View {

    @State private var isShowingNaverMapsTest = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "car.fill")
                    .imageScale(.large)
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Drive in Gyeongbuk")
                    .font(.title2.bold())
                Text("Navigation for foreign drivers in Gyeongsangbuk-do")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // 제품 UI 는 아직 없다. 서비스 계층 검증용 화면으로만 연결해 둔다.
            Button {
                isShowingNaverMapsTest = true
            } label: {
                Label("NaverMaps 서비스 테스트", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .fullScreenCover(isPresented: $isShowingNaverMapsTest) {
            NaverMapsTestView(onClose: { isShowingNaverMapsTest = false })
        }
    }
}

#Preview {
    HomeView()
}
