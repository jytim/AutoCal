import SwiftUI

/// 設定：搜尋金鑰、模型後端。全部存在本機 UserDefaults。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("brave.apiKey") private var braveKey = ""
    @AppStorage(AppConfig.gatewayKeyName, store: AppConfig.sharedDefaults) private var gatewayKey = ""
    @AppStorage("llm.baseURL") private var llmBaseURL = ""
    @AppStorage("llm.model") private var llmModel = ""
    @AppStorage(EventColor.followKey) private var followCalendarColor = true
    @AppStorage("ui.dayStartHour") private var dayStart = 8
    @AppStorage("ui.showWeekView") private var showWeekView = true
    @AppStorage("ui.dayEndHour") private var dayEnd = 22

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        WallpaperSettingsView()
                    } label: {
                        Label("鎖定畫面桌布", systemImage: "iphone.gen3")
                    }
                }

                Section {
                    NavigationLink {
                        CourseManageView()
                    } label: {
                        Label("課堂管理", systemImage: "books.vertical")
                    }
                }

                Section {
                    Toggle("顯示週檢視", isOn: $showWeekView)
                }

                Section {
                    Picker("開始", selection: $dayStart) {
                        ForEach(0...12, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    Picker("結束", selection: $dayEnd) {
                        ForEach(13...24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                } header: {
                    Text("日程顯示時段")
                } footer: {
                    Text("超出的行程會自動往外擴。")
                }

                Section {
                    Toggle("行程顏色跟隨行事曆", isOn: $followCalendarColor)
                }

                ClassReminderSection()

                Section {
                    NavigationLink {
                        ShareLogView()
                    } label: {
                        Label("分享診斷紀錄", systemImage: "stethoscope")
                    }
                } footer: {
                    Text("分享閃退時，用來回報問題。")
                }

                Section {
                    SecureField("貼上邀請金鑰", text: $gatewayKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("邀請金鑰")
                } footer: {
                    Text("向開發者索取，只存在這支手機。")
                }

                Section {
                    SecureField("貼上 Brave 搜尋金鑰", text: $braveKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("網路搜尋（Brave API）")
                } footer: {
                    Text("api-dashboard.search.brave.com 申請，只存在這支手機。")
                }

                Section {
                    TextField("模型 API 位址", text: $llmBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("模型名稱", text: $llmModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("模型後端")
                } footer: {
                    Text("留空使用官方伺服器。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
