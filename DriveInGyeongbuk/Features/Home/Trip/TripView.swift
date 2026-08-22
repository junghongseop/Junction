//
//  TripView.swift
//  DriveInGyeongbuk
//
//  ⚠️ 아직 껍데기(stub)입니다.
//
//  피그마 시안에는 탭 자리만 있고 화면 디자인은 아직 없다.
//  지난 주행 기록 · 저장한 목적지를 보여 줄 자리로 잡아 두었다.
//

import SwiftUI

struct TripView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No trips yet",
                systemImage: "bag",
                description: Text("Your saved destinations and past drives will show up here.")
            )
            .navigationTitle("Trip")
        }
    }
}

#Preview {
    TripView()
}
