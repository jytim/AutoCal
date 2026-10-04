import SwiftUI
import PhotosUI
import UIKit

/// 新增課堂的共用流程：手動新增、從截圖匯入（可多張）。
/// 課表分頁和「設定 → 課堂管理」都用同一套。
@MainActor
final class CourseAddModel: ObservableObject {
    struct FormTarget: Identifiable { let id = UUID(); let course: Course? }
    struct ImportBox: Identifiable {
        let id = UUID()
        let drafts: [CourseDraft]
        var sourceCount = 1
        var rawCount = 0
        var failures: [String] = []
    }

    @Published var formTarget: FormTarget?
    @Published var importBox: ImportBox?
    @Published var showPhotoPicker = false
    @Published var pickedPhotos: [PhotosPickerItem] = []
    @Published var importProgress = "正在辨識課表…"
    @Published var importing = false
    @Published var importError: String?

    /// 一張課表放不下時可以多選幾張截圖：逐張辨識，再合併重複與被截斷的課。
    func importFromPhotos(_ items: [PhotosPickerItem]) async {
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
                var parsed = try await LLMClient().parseCourses(imageData: Self.downscaled(data))
                for k in parsed.indices { parsed[k].sourceIndex = i }
                all += parsed
            } catch {
                failures.append("第 \(i + 1) 張：\(error.localizedDescription)")
            }
        }

        let merged = CourseDraft.merged(CourseDraft.assigningWeekdays(all))
        if merged.isEmpty {
            importError = failures.isEmpty ? "截圖裡沒有辨識到課堂" : failures.joined(separator: "\n")
        } else {
            importBox = ImportBox(drafts: merged, sourceCount: items.count,
                                  rawCount: all.count, failures: failures)
        }
    }

    /// 縮小並轉成 JPEG 加快上傳。一般截圖長邊 1600px；很長的長截圖（高是寬的兩倍以上）
    /// 保留到 3000px，不然縮太小字會看不清楚。
    static func downscaled(_ data: Data) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let long = max(img.size.width, img.size.height)
        let short = max(1, min(img.size.width, img.size.height))
        let maxSide: CGFloat = (long / short) > 2 ? 3000 : 1600
        let scale = min(1, maxSide / long)
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let out = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.85) ?? data
    }

}

struct CourseAddMenu: View {
    @ObservedObject var model: CourseAddModel

    var body: some View {
        Menu {
            Button { model.formTarget = .init(course: nil) } label: {
                Label("手動新增課堂", systemImage: "plus")
            }
            Button { model.showPhotoPicker = true } label: {
                Label("從截圖匯入課表（可多張）", systemImage: "photo.on.rectangle")
            }
        } label: { Image(systemName: "plus") }
    }
}

private struct CourseAddFlow: ViewModifier {
    @ObservedObject var model: CourseAddModel

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $model.showPhotoPicker, selection: $model.pickedPhotos,
                          maxSelectionCount: 8, matching: .images)
            .onChange(of: model.pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                Task { await model.importFromPhotos(items) }
            }
            .overlay {
                if model.importing {
                    ProgressView(model.importProgress)
                        .padding(24)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .alert("匯入失敗", isPresented: Binding(get: { model.importError != nil },
                                                  set: { if !$0 { model.importError = nil } })) {
                Button("好") { model.importError = nil }
            } message: { Text(model.importError ?? "") }
            .sheet(item: $model.formTarget) { target in CourseFormView(editing: target.course) }
            .sheet(item: $model.importBox) { box in
                CourseImportView(drafts: box.drafts, sourceCount: box.sourceCount,
                                 rawCount: box.rawCount, failures: box.failures)
            }
    }
}


extension View {
    func courseAddFlow(_ model: CourseAddModel) -> some View { modifier(CourseAddFlow(model: model)) }
}
