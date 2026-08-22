//
//  AppInfoView.swift
//  DriveInGyeongbuk
//
//  홈 화면 우측 상단 안내 버튼이 여는 시트.
//
//  외국인 운전자가 이 앱으로 무엇을 얻는지, 그리고 어디까지 믿어도 되는지를 알린다.
//  "경상북도 밖에서는 제한속도·주차·단속 정보가 비어 있다"는 건 반드시 미리 말해야 해서
//  여기에 적어 두었다. (데이터셋이 경북 전용이다)
//

import SwiftUI

struct AppInfoView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("What this app does") {
                    feature(icon: "gauge.with.needle",
                            title: "Speed limits",
                            detail: "Shows the posted limit for the road you are on and warns you before you go over.")
                    feature(icon: "parkingsign.circle",
                            title: "Parking near your destination",
                            detail: "Finds nearby parking lots with walking time.")
                    feature(icon: "exclamationmark.triangle",
                            title: "No-parking zones",
                            detail: "Warns you about streets where stopping is not allowed right now.")
                }

                Section("Good to know") {
                    Label("Data covers Gyeongsangbuk-do only. Outside the province, guidance is unavailable.",
                          systemImage: "map")
                    Label("Speed limits come from the national node-link dataset, not from roadside signs. Always follow the sign you see.",
                          systemImage: "signpost.right")
                }

                Section("Sources") {
                    LabeledContent("Map & routing", value: "NAVER Cloud Platform")
                    LabeledContent("Speed limits", value: "국가교통정보센터 표준노드링크")
                    LabeledContent("Parking & enforcement", value: "경상북도 공공데이터")
                }
            }
            .navigationTitle("Drive in Gyeongbuk")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }
}

#Preview {
    AppInfoView()
}
