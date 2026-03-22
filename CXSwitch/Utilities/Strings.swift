import Foundation

enum Strings {
    nonisolated(unsafe) static var languageProvider: () -> String = { Preferences.defaultLanguage }

    static func L(_ zh: String, en: String) -> String {
        let language = languageProvider().lowercased()
        return language == "en" ? en : zh
    }

    static var currentAccount: String { L("当前账户", en: "Current Account") }
    static var switchTo: String { L("切换到", en: "Switch To") }
    static var addAccount: String { L("添加账户…", en: "Add Account…") }
    static var importToken: String { L("导入 Token", en: "Import Token") }
    static var importTokenPlaceholder: String { L("粘贴 Refresh Token", en: "Paste refresh token") }
    static var pasteAndImport: String { L("从剪贴板粘贴并导入", en: "Paste from clipboard and import") }
    static var refresh: String { L("刷新", en: "Refresh") }
    static var settings: String { L("设置", en: "Settings") }
    static var status: String { L("状态", en: "Status") }
    static var quit: String { L("退出 CX Switch", en: "Quit CX Switch") }
    static var maskEmails: String { L("邮箱脱敏", en: "Mask Emails") }
    static var openDataFolder: String { L("打开数据文件夹", en: "Open Data Folder") }
    static var noActiveAccount: String { L("未检测到活跃账户，请切换或添加", en: "No active account, switch or add one") }
    static var saveCurrentAccount: String { L("保存当前账户", en: "Save Current Account") }
    static var missingAuthForSelectedAccount: String { L("所选账户缺少认证信息", en: "Missing auth for selected account") }
    static var missingAuthJSON: String { L("缺少 auth.json", en: "Missing auth.json") }
    static var invalidRefreshToken: String { L("无效的刷新令牌", en: "Invalid refresh token") }
    static var accountInfoUnavailableAfterImport: String { L("导入后无法读取账户信息", en: "Account info unavailable after import") }
    static var missingAuth: String { L("缺少认证信息", en: "Missing auth") }
    static var missingToken: String { L("缺少访问令牌", en: "Missing token") }
    static var unknownError: String { L("未知错误", en: "Unknown error") }
    static var loginPreparing: String { L("准备中", en: "Preparing") }
    static var loginWaiting: String { L("等待登录完成", en: "Waiting for login") }
    static var loginCompleted: String { L("已完成", en: "Completed") }
    static var loginCancelled: String { L("已取消", en: "Cancelled") }

    static func planTypeDisplayName(for planType: PlanType) -> String {
        switch planType {
        case .free:
            return "Free"
        case .go:
            return "Go"
        case .plus:
            return "Plus"
        case .pro:
            return "Pro"
        case .team:
            return "Team"
        case .business:
            return "Business"
        case .enterprise:
            return "Enterprise"
        case .edu:
            return "Edu"
        case .unknown:
            return "Unknown Plan"
        }
    }

}
