import Foundation

/// 後端與模型設定。預設指向家裡 3090 那台（透過 WireGuard VPN 連得到）。
/// 之後可做成設定畫面讓使用者修改；先用 UserDefaults 覆寫。
enum AppConfig {
    static var baseURL: URL {
        // 預設用 192.168.0.45 的 MoE 伺服器（比 3090 快約 12 倍，也支援看圖）。
        let s = UserDefaults.standard.string(forKey: "llm.baseURL")
            ?? "http://192.168.0.45:8990/v1"
        return URL(string: s)!
    }

    static var model: String {
        UserDefaults.standard.string(forKey: "llm.model")
            ?? "nvidia-Qwen3.6-35B-A3B-NVFP4"
    }

    /// 校園行事曆（ICS 格式）。預設為台科大 114 學年度行事曆。
    /// 每學年更新時，把新的 ICS 網址存進 UserDefaults 即可。
    static var campusCalendarURL: URL? {
        let s = UserDefaults.standard.string(forKey: "campus.icsURL")
            ?? "https://www.academic.ntust.edu.tw/var/file/48/1048/img/788923882.ics"
        return URL(string: s)
    }

    /// Brave 搜尋 API 金鑰。只存在本機 UserDefaults，不進版本庫。
    static var braveAPIKey: String? {
        UserDefaults.standard.string(forKey: "brave.apiKey")
    }
}
