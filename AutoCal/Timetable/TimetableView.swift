import SwiftUI
import PhotosUI
import UIKit

/// 課表式的一週時間塊檢視：事件是方塊，週一到週五的空檔標成「空堂」。
struct TimetableView: View {
    @StateObject private var vm = TimetableViewModel()
    @ObservedObject private var courseStore = CourseStore.shared
    @State private var selected: TimetableEvent?
    @State private var formTarget: FormTarget?
    @State private var importBox: ImportBox?
    @State private var showPhotoPicker = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var importProgress = "正在辨識課表…"
    @State private var importing = false
    @State private var importError: String?

    private struct FormTarget: Identifiable { let id = UUID(); let course: Course? }
    private struct ImportBox: Identifiable {
        let id = UUID()
        let drafts: [CourseDraft]
        var sourceCount = 1
        var rawCount = 0
        var failures: [String] = []
    }

    private let hourHeight: CGFloat = 46
    private let timeColWidth: CGFloat = 34
    private let headerHeight: CGFloat = 44

    private var totalHours: Int { TimetableViewModel.endHour - TimetableViewModel.startHour }

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M/d"
        return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "E"
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
            VStack(spacing: 0) {
                weekBar
                if vm.accessDenied {
                    Label("沒有行事曆權限，目前只顯示課堂。可到「設定」開啟。", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }
                GeometryReader { geo in
                    let colWidth = (geo.size.width - timeColWidth) / 7
                    VStack(spacing: 0) {
                        dayHeader(colWidth: colWidth)
                        ScrollView {
                            grid(colWidth: colWidth)
                                .frame(height: CGFloat(totalHours) * hourHeight, alignment: .topLeading)
                                .padding(.bottom, 80)
                        }
                    }
                }
            }
            .navigationTitle("課表")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Task { await vm.load() } }
            .onReceive(courseStore.$courses) { _ in Task { await vm.load() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { formTarget = FormTarget(course: nil) } label: {
                            Label("手動新增課堂", systemImage: "plus")
                        }
                        Button { showPhotoPicker = true } label: {
                            Label("從截圖匯入課表（可多張）", systemImage: "photo.on.rectangle")
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhotos,
                          maxSelectionCount: 8, matching: .images)
            .onChange(of: pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                Task { await importFromPhotos(items) }
            }
            .overlay {
                if importing {
                    ProgressView(importProgress)
                        .padding(24)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .alert("匯入失敗", isPresented: Binding(get: { importError != nil },
                                                  set: { if !$0 { importError = nil } })) {
                Button("好") { importError = nil }
            } message: { Text(importError ?? "") }
            .sheet(item: $selected) { event in
                EventDetailSheet(
                    event: event,
                    onEdit: {
                        guard let id = event.courseID,
                              let c = courseStore.courses.first(where: { $0.id == id }) else { return }
                        selected = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            formTarget = FormTarget(course: c)
                        }
                    },
                    onSkip: {
                        guard let id = event.courseID else { return }
                        CourseStore.shared.skip(courseID: id, on: event.start)
                        selected = nil
                    },
                    onDelete: {
                        guard let id = event.courseID else { return }
                        CourseStore.shared.delete(id: id)
                        selected = nil
                    })
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $formTarget) { target in CourseFormView(editing: target.course) }
            .sheet(item: $importBox) { box in
                CourseImportView(drafts: box.drafts, sourceCount: box.sourceCount,
                                 rawCount: box.rawCount, failures: box.failures)
            }
        }
    }

    // MARK: - 課表截圖匯入

    /// 一張課表放不下時可以多選幾張截圖：逐張辨識，再合併重複與被截斷的課。
    private func importFromPhotos(_ items: [PhotosPickerItem]) async {
        importing = true
        defer { importing = false; pickedPhotos = [] }

        var all: [CourseDraft] = []
        var failures: [String] = []
        for (i, item) in items.enumerated() {
            importProgress = items.count > 1 ? "正在辨識第 \(i + 1) / \(items.count) 張…" : "正在辨識課表…"
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failures.append("第 \(i + 1) 張：讀不到圖片"); continue
                }
                all += try await LLMClient().parseCourses(imageData: Self.downscaled(data),
                                                            known: all.filter { $0.weekday != 0 })
            } catch {
                failures.append("第 \(i + 1) 張：\(error.localizedDescription)")
            }
        }

        let merged = CourseDraft.merged(all)
        if merged.isEmpty {
            importError = failures.isEmpty ? "截圖裡沒有辨識到課堂" : failures.joined(separator: "\n")
        } else {
            importBox = ImportBox(drafts: merged, sourceCount: items.count,
                                  rawCount: all.count, failures: failures)
        }
    }

    /// 縮小並轉成 JPEG 加快上傳。一般截圖長邊 1600px；很長的長截圖（高是寬的兩倍以上）
    /// 保留到 3000px，不然縮太小字會看不清楚。
    private static func downscaled(_ data: Data) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let long = max(img.size.width, img.size.height)
        let short = max(1, min(img.size.width, img.size.height))
        let maxSide: CGFloat = (long / short) > 2 ? 3000 : 1600
        let scale = min(1, maxSide / long)
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let out = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.85) ?? data
    }

    // MARK: - 週切換列

    private var weekBar: some View {
        HStack {
            Button { vm.shiftWeek(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text("\(Self.monthDay.string(from: vm.weekStart)) – \(Self.monthDay.string(from: vm.days.last ?? vm.weekStart))")
                    .font(.subheadline.bold())
                Button("回到本週") { vm.goToThisWeek() }
                    .font(.caption)
            }
            Spacer()
            Button { vm.shiftWeek(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - 星期標頭

    private func dayHeader(colWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColWidth)
            ForEach(vm.days, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 1) {
                    Text(Self.weekday.string(from: day))
                        .font(.caption2)
                    Text(Self.monthDay.string(from: day))
                        .font(.caption2.bold())
                }
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: colWidth, height: headerHeight - 8)
                .background(isToday ? Color.accentColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(height: headerHeight)
    }

    // MARK: - 格子本體

    private func grid(colWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // 小時橫線與標籤
            ForEach(0..<totalHours, id: \.self) { i in
                let y = CGFloat(i) * hourHeight
                Text(String(format: "%02d", TimetableViewModel.startHour + i))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: timeColWidth - 4, alignment: .trailing)
                    .offset(x: 0, y: y - 6)
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 0.5)
                    .padding(.leading, timeColWidth)
                    .offset(y: y)
            }

            // 今天那一欄淡淡上色
            if let idx = vm.days.firstIndex(where: { Calendar.current.isDateInToday($0) }) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.07))
                    .frame(width: colWidth, height: CGFloat(totalHours) * hourHeight)
                    .offset(x: timeColWidth + CGFloat(idx) * colWidth)
            }
            // 每天之間的細直線：從星期標頭一路往下對照
            ForEach(0...7, id: \.self) { i in
                Rectangle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: 0.5, height: CGFloat(totalHours) * hourHeight)
                    .offset(x: timeColWidth + CGFloat(i) * colWidth)
            }

            // 每天一欄：空堂在底、事件方塊在上
            ForEach(Array(vm.days.enumerated()), id: \.offset) { index, day in
                let x = timeColWidth + CGFloat(index) * colWidth

                if vm.isWeekday(day) {
                    ForEach(vm.freeSlots(on: day)) { slot in
                        freeBlock(slot, colWidth: colWidth)
                            .offset(x: x, y: yPosition(of: slot.start))
                    }
                }

                let dayEvents = vm.events(on: day)
                let lanes = vm.lanes(for: dayEvents)
                ForEach(dayEvents) { e in
                    // 撞時段的行程做成「疊在一起的卡片」：後面的往右露出一點邊（保持直的），
                    // 比對半切成窄條寬，字才放得下。
                    let info = lanes[e.id] ?? (0, 1)
                    let stagger: CGFloat = info.count > 1 ? 4 : 0
                    let cardWidth = colWidth - stagger * CGFloat(info.count - 1)
                    eventBlock(e, width: cardWidth)
                        .shadow(color: .black.opacity(info.count > 1 ? 0.28 : 0.1),
                                radius: 1.5, x: 0, y: 1)
                        .offset(x: x + stagger * CGFloat(info.lane),
                                y: yPosition(of: e.start))
                        .zIndex(Double(info.lane))
                        .onTapGesture { selected = e }
                }
            }

            // 現在時間紅線（只在本週、且在顯示範圍內）
            nowLine(colWidth: colWidth)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func yPosition(of date: Date) -> CGFloat {
        let c = Calendar.current
        let minutes = c.component(.hour, from: date) * 60 + c.component(.minute, from: date)
        let rel = CGFloat(minutes - TimetableViewModel.startHour * 60) / 60
        return max(rel, 0) * hourHeight
    }

    private func eventBlock(_ e: TimetableEvent, width: CGFloat) -> some View {
        let top = yPosition(of: e.start)
        let bottom = min(yPosition(of: e.end), CGFloat(totalHours) * hourHeight)
        let height = max(bottom - top, 20)
        return VStack(alignment: .leading, spacing: 1) {
            Text(e.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(height > 44 ? 3 : 1)
            if height > 30 {
                Text("\(Self.hm.string(from: e.start))–\(Self.hm.string(from: e.end))")
                    .font(.system(size: 8).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(0.92)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(width: width - 2, height: height - 1, alignment: .topLeading)
        .background(e.color)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.7), lineWidth: 0.8))
        .padding(.leading, 1)
    }

    private func freeBlock(_ slot: FreeSlot, colWidth: CGFloat) -> some View {
        let height = CGFloat(slot.duration / 3600) * hourHeight
        return RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.green.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .background(Color.green.opacity(0.07).clipShape(RoundedRectangle(cornerRadius: 5)))
            .overlay(alignment: .top) {
                // 空堂不寫字，只寫起訖時間
                Text("\(Self.hm.string(from: slot.start))–\(Self.hm.string(from: slot.end))")
                    .font(.system(size: 8).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color.green)
                    .padding(.top, 3)
                    .padding(.horizontal, 2)
            }
            .frame(width: colWidth - 2, height: height - 1)
            .padding(.leading, 1)
    }

    @ViewBuilder
    private func nowLine(colWidth: CGFloat) -> some View {
        let now = Date()
        if let idx = vm.days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: now) }) {
            let y = yPosition(of: now)
            if y > 0 && y < CGFloat(totalHours) * hourHeight {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: colWidth * 7 + 0, height: 1)
                    .offset(x: timeColWidth + 0, y: y)
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(x: timeColWidth + CGFloat(idx) * colWidth - 3, y: y - 3)
            }
        }
    }
}

// MARK: - 詳情

private struct EventDetailSheet: View {
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
