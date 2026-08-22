//
//  SettingsView.swift
//  DriveInGyeongbuk
//
//  ⚠️ 설정 항목 자체는 아직 껍데기(stub)입니다.
//
//  피그마 시안에는 탭 자리만 있고 화면 디자인은 아직 없다.
//  다만 서비스 계층 검증용 화면(`Test/`)이 지금까지 HomeView 에 붙어 있었으므로,
//  홈이 제품 UI 로 바뀌면서 갈 곳을 잃지 않도록 "Developer" 섹션으로 옮겨 두었다.
//  제품 출시 전에는 이 섹션을 통째로 걷어내야 한다.
//

import SwiftUI

struct SettingsView: View {

    @State private var isShowingNaverMapsTest = false
    @State private var isShowingSpeedLimitTest = false
    @State private var isShowingParkingTest = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Coverage", value: "Gyeongsangbuk-do")
                    LabeledContent("Version", value: Self.versionText)
                } header: {
                    Text("About")
                } footer: {
                    Text("Guidance is only available inside Gyeongsangbuk-do.")
                }

                // TODO: 제품 출시 전에 이 섹션을 걷어낸다. 서비스 계층 수동 검증용이다.
                Section("Developer") {
                    Button {
                        isShowingNaverMapsTest = true
                    } label: {
                        Label("NaverMaps 서비스 테스트", systemImage: "map")
                    }

                    Button {
                        isShowingSpeedLimitTest = true
                    } label: {
                        Label("SpeedLimit 서비스 테스트", systemImage: "gauge.with.needle")
                    }

                    Button {
                        isShowingParkingTest = true
                    } label: {
                        Label("Parking · Enforcement 서비스 테스트", systemImage: "parkingsign.circle")
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .fullScreenCover(isPresented: $isShowingNaverMapsTest) {
            NaverMapsTestView(onClose: { isShowingNaverMapsTest = false })
        }
        .fullScreenCover(isPresented: $isShowingSpeedLimitTest) {
            SpeedLimitTestView(onClose: { isShowingSpeedLimitTest = false })
        }
        .fullScreenCover(isPresented: $isShowingParkingTest) {
            ParkingTestView(onClose: { isShowingParkingTest = false })
        }
    }

    private static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "-"
    }
}

#Preview {
    SettingsView()
}
