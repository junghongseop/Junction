//
//  HomeView.swift
//  DriveInGyeongbuk
//
//  Created by 정홍섭 on 8/22/26.
//

import SwiftUI

struct HomeView: View {

    @State private var isShowingNaverMapsTest = false
    @State private var isShowingLocationSearchTest = false
    @State private var isShowingSpeedLimitTest = false
    @State private var isShowingParkingTest = false

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
            VStack(spacing: 12) {
                Button {
                    isShowingNaverMapsTest = true
                } label: {
                    Label("NaverMaps 서비스 테스트", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    isShowingLocationSearchTest = true
                } label: {
                    Label("도착지 검색 API 테스트", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    isShowingSpeedLimitTest = true
                } label: {
                    Label("SpeedLimit 서비스 테스트", systemImage: "gauge.with.needle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    isShowingParkingTest = true
                } label: {
                    Label("Parking · Enforcement 서비스 테스트", systemImage: "parkingsign.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .fullScreenCover(isPresented: $isShowingNaverMapsTest) {
            NaverMapsTestView(onClose: { isShowingNaverMapsTest = false })
        }
        .fullScreenCover(isPresented: $isShowingLocationSearchTest) {
            NaverLocationSearchTestView(onClose: { isShowingLocationSearchTest = false })
        }
        .fullScreenCover(isPresented: $isShowingSpeedLimitTest) {
            SpeedLimitTestView(onClose: { isShowingSpeedLimitTest = false })
        }
        .fullScreenCover(isPresented: $isShowingParkingTest) {
            ParkingTestView(onClose: { isShowingParkingTest = false })
        }
    }
}

#Preview {
    HomeView()
}
