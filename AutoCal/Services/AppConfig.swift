import Foundation

/// 後端與模型設定。預設連公開閘道，進階使用者可在設定頁改成自訂位址。
enum AppConfig {
    /// App 與分享擴充功能（以及之後的小工具）共用資料的 App Group。
    static let appGroup = "group.com.jiangyanting.autocal"

    /// 一個模型後端：API 位址 + 模型名稱。
    struct Endpoint { let baseURL: URL; let model: String }

    /// 正式後端：公開閘道（HTTPS、需要邀請金鑰）。模型選擇與備援都在閘道那邊處理。
    static let gatewayURL = URL(string: "https://api.justaddcal.com/v1")!
    static let gatewayModel = "autocal"

    /// App 與分享擴充功能共用的設定（金鑰要讓分享選單也讀得到）。
    static let sharedDefaults = UserDefaults(suiteName: appGroup) ?? .standard
    static let gatewayKeyName = "gateway.apiKey"
    static var gatewayKey: String? {
        let k = sharedDefaults.string(forKey: gatewayKeyName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty ?? true) ? nil : k
    }

    /// 要嘗試的後端清單。使用者在設定頁填了自訂位址就只用那一個，否則用公開閘道。
    static var endpoints: [Endpoint] {
        if let custom = UserDefaults.standard.string(forKey: "llm.baseURL"),
           !custom.isEmpty, let url = URL(string: custom) {
            let model = UserDefaults.standard.string(forKey: "llm.model") ?? ""
            return [Endpoint(baseURL: url, model: model)]
        }
        return [Endpoint(baseURL: gatewayURL, model: gatewayModel)]
    }

    /// Brave 搜尋 API 金鑰。只存在本機 UserDefaults，不進版本庫。
    static var braveAPIKey: String? {
        UserDefaults.standard.string(forKey: "brave.apiKey")
    }
}
