import Foundation

/// 後端與模型設定。預設指向家裡 3090 那台（透過 WireGuard VPN 連得到）。
/// 之後可做成設定畫面讓使用者修改；先用 UserDefaults 覆寫。
enum AppConfig {
    /// App 與分享擴充功能（以及之後的小工具）共用資料的 App Group。
    static let appGroup = "group.com.jiangyanting.autocal"

    /// 一個模型後端：API 位址 + 模型名稱。
    struct Endpoint { let baseURL: URL; let model: String }

    /// 要嘗試的後端清單（依序）。
    /// 若使用者在設定頁填了自訂位址，就只用那一個；
    /// 否則預設「0.45 MoE（快）優先，連不到退回 3090」。
    static var endpoints: [Endpoint] {
        if let custom = UserDefaults.standard.string(forKey: "llm.baseURL"),
           !custom.isEmpty, let url = URL(string: custom) {
            let model = UserDefaults.standard.string(forKey: "llm.model") ?? ""
            return [Endpoint(baseURL: url, model: model)]
        }
        return [
            Endpoint(baseURL: URL(string: "http://192.168.0.45:8990/v1")!,
                     model: "nvidia-Qwen3.6-35B-A3B-NVFP4"),
            Endpoint(baseURL: URL(string: "http://192.168.2.230:8990/v1")!,
                     model: "/home/wahaha/models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf")
        ]
    }

    /// Brave 搜尋 API 金鑰。只存在本機 UserDefaults，不進版本庫。
    static var braveAPIKey: String? {
        UserDefaults.standard.string(forKey: "brave.apiKey")
    }
}
