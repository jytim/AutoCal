import SwiftUI

/// 設定 → 加入紀錄：記吧最近加入的行程與待辦（30 天內），可整批或單筆刪除。
struct AddHistoryView: View {
    @State private var batches = AddHistory.load()
    @State private var message: String?

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "M/d HH:mm"; return f
    }()
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "M/d (E)"; return f
    }()
    private static let ev: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "M/d (E) HH:mm"; return f
    }()

    var body: some View {
        List {
            if let m = message { Section { Text(m).font(.footnote).foregroundStyle(.secondary) } }
            if batches.isEmpty {
                Text("還沒有加入紀錄。").foregroundStyle(.secondary)
            }
            ForEach(batches) { b in
                Section {
                    ForEach(b.records) { r in
                        HStack {
                            Image(systemName: r.isEvent ? "calendar" : "checklist")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).lineLimit(1)
                                if let s = r.start {
                                    // 整天或只有日期的項目（午夜 00:00）只顯示日期
                                    Text((ItemCard.hasClockTime(s) ? Self.ev : Self.dayOnly).string(from: s))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) { Task { await remove([r]) } } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(Self.df.string(from: b.date))　共 \(b.records.count) 項")
                        Spacer()
                        Button("整批刪除", role: .destructive) { Task { await remove(b.records) } }
                            .font(.footnote)
                    }
                }
            }
        }
        .navigationTitle("加入紀錄")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func remove(_ records: [AddedRecord]) async {
        let res = await AddHistory.undo(records)
        message = AddHistory.summary(res)
        batches = AddHistory.load()
    }
}
