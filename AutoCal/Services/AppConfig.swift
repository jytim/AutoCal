import Foundation

/// 後端與模型設定。預設指向家裡 3090 那台（透過 WireGuard VPN 連得到）。
/// 之後可做成設定畫面讓使用者修改；先用 UserDefaults 覆寫。
enum AppConfig {
    static var baseURL: URL {
        let s = UserDefaults.standard.string(forKey: "llm.baseURL")
            ?? "http://192.168.2.230:8990/v1"
        return URL(string: s)!
    }

    static var model: String {
        UserDefaults.standard.string(forKey: "llm.model")
            ?? "/home/wahaha/models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf"
    }

    /// 校園行事曆（ICS 格式）。預設為台科大 114 學年度行事曆。
    /// 每學年更新時，把新的 ICS 網址存進 UserDefaults 即可。
    static var campusCalendarURL: URL? {
        let s = UserDefaults.standard.string(forKey: "campus.icsURL")
            ?? "https://www.academic.ntust.edu.tw/var/file/48/1048/img/788923882.ics"
        return URL(string: s)
    }
}
