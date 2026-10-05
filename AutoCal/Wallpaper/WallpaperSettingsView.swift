import SwiftUI
import Photos
import EventKit

/// 鎖定畫面桌布：預覽、存到相簿，以及自動更新的設定教學。
struct WallpaperSettingsView: View {
    @State private var image: UIImage?
    @State private var status: String?

    var body: some View {
        List {
            Section {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 8, leading: 40, bottom: 8, trailing: 40))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }

                HStack {
                    Button { Task { await refresh() } } label: {
                        Label("更新預覽", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("鎖定畫面桌布", image: Image(uiImage: image))) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    }
                    Spacer()
                    Button { Task { await saveToPhotos() } } label: {
                        Label("存到相簿", systemImage: "photo.badge.plus")
                    }
                    .disabled(image == nil)
                }
                .buttonStyle(.borderless)
                .font(.footnote)

                if let status {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("目前的桌布")
            } footer: {
                Text("捷徑會拿這張當桌布，是靜態圖片，右上角標示更新時間。")
            }

            Section {
                step(1, "開啟「捷徑」App，新增一個捷徑。")
                step(2, "加入動作「產生今日鎖定畫面桌布」（AutoCal），再加入動作「設定桌布」，來源選上一個動作的結果、位置選「鎖定畫面」，並把「顯示預覽」關掉。")
                step(3, "到「自動化」分頁，新增個人自動化，選一個時機（見下方），動作選剛才的捷徑，並關閉「執行前先詢問」。")
            } header: {
                Text("設定自動更新")
            } footer: {
                Text("鎖定畫面要是一般照片桌布，不能是「照片輪播」。")
            }

            Section {
                tip("每天早上", "「時間」→ 每天 07:00。")
                tip("離開 AutoCal 時", "「App」→ 關閉 AutoCal。剛新增完行程、離開 App 就會更新。")
                tip("切換專注模式", "「專注模式」→ 開啟或關閉。上課前後常會切換。")
                tip("連接充電器", "「充電器」→ 已連接。")
            } header: {
                Text("建議的觸發時機")
            } footer: {
                Text("「時間」只能設每天、每週或每月。")
            }
        }
        .navigationTitle("鎖定畫面桌布")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.footnote.bold())
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Circle())
            Text(text).font(.subheadline)
        }
    }

    private func tip(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: - 動作

    private func refresh() async {
        // 在 App 裡開這一頁時才會跳行事曆權限；捷徑背景執行時不會跳，所以要先在這裡授權過
        _ = try? await EKEventStore().requestFullAccessToEvents()
        image = WallpaperRenderer.image()
    }

    private func saveToPhotos() async {
        guard let image else { return }
        let auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard auth == .authorized || auth == .limited else {
            status = "沒有相簿權限，請到「設定」開啟。"
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            status = "已存到相簿。"
        } catch {
            status = "存到相簿失敗：\(error.localizedDescription)"
        }
    }
}
