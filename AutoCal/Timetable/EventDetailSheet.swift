import SwiftUI

/// 行程 / 課堂的詳情頁（課表與日程共用）。課堂多三個動作：編輯、這天停課、刪除整門課。
struct EventDetailSheet: View {
    let event: TimetableEvent
    var onEdit: () -> Void = {}
    var onSkip: () -> Void = {}
    var onDelete: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    private static let full: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M/d (E) HH:mm"
        return f
    }()
    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(event.title).font(.headline)
                    Label("\(Self.full.string(from: event.start)) – \(Self.hm.string(from: event.end))",
                          systemImage: "clock")
                    if let loc = event.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse")
                    }
                }
                if let notes = event.notes, !notes.isEmpty {
                    Section("備註 / AI 決策紀錄") {
                        Text(notes).font(.footnote)
                    }
                }
                if event.isCourse {
                    Section {
                        Button { onEdit() } label: { Label("編輯這門課", systemImage: "pencil") }
                        Button { onSkip() } label: { Label("這天停課", systemImage: "moon.zzz") }
                        Button(role: .destructive) { onDelete() } label: {
                            Label("刪除整門課", systemImage: "trash")
                        }
                    } footer: {
                        Text("課堂只存在 AutoCal 的課表，不會出現在行事曆。")
                    }
                }
            }
            .navigationTitle(event.isCourse ? "課堂詳情" : "行程詳情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
