import Foundation

/// 生图接口形态：不同上游开放的路子不一样
enum APIMode: String, CaseIterable {
    case chat
    case images

    var title: String {
        switch self {
        case .chat: return "聊天接口"
        case .images: return "图片接口"
        }
    }

    var shortTitle: String {
        switch self {
        case .chat: return "聊天"
        case .images: return "图片"
        }
    }

    var detail: String {
        switch self {
        case .chat:
            return "POST /v1/chat/completions，提示词当消息发（AxonHub 的 grok-imagine 走这个）"
        case .images:
            return "POST /v1/images/generations，标准生图接口；上游报 permission_denied（只开放图片接口）就切到它"
        }
    }
}

/// 运行时设置（持久化在 UserDefaults，只存在本机 App 沙盒里）。
/// 仓库不内置任何端点与 Key：全部由用户在 App 设置页自己填。
final class Settings: ObservableObject {
    /// 只作为输入框的占位示例，不是默认值
    static let exampleBase = "https://hub.oaifree.com"
    static let exampleModel = "grok-imagine-image-2.0"

    /// 模型快选（只是快捷项，设置页可以随便填别的）
    static let modelPresets: [String] = [
        "grok-imagine-image-2.0",
        "grok-imagine-image-quality",
        "grok-imagine-image",
        "grok-imagine-image-lite",
    ]

    private enum Key {
        static let base = "base"
        static let apiKey = "apiKey"
        static let apiMode = "apiMode"
        static let model = "model"
        static let proxy = "proxy"
    }

    @Published var base: String { didSet { persist() } }
    @Published var apiKey: String { didSet { persist() } }
    @Published var apiMode: APIMode { didSet { persist() } }
    @Published var model: String { didSet { persist() } }
    @Published var proxy: String { didSet { persist() } }

    /// 从上游 `GET /v1/models` 拉到的模型（只在内存里，不落盘）
    @Published var upstreamModels: [String] = []

    /// 选择器候选：上游列表优先，预设补齐（两者都不白名单，模型栏仍可手输）
    var modelChoices: [String] {
        var list: [String] = []
        for name in upstreamModels where !list.contains(name) {
            list.append(name)
        }
        for name in Settings.modelPresets where !list.contains(name) {
            list.append(name)
        }
        return list
    }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        base = d.string(forKey: Key.base) ?? ""
        apiKey = d.string(forKey: Key.apiKey) ?? ""
        apiMode = APIMode(rawValue: d.string(forKey: Key.apiMode) ?? "") ?? .chat
        model = d.string(forKey: Key.model) ?? Settings.exampleModel
        proxy = d.string(forKey: Key.proxy) ?? ""
    }

    /// 端点和 Key 都填了才能生成
    var isConfigured: Bool {
        !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clearCredentials() {
        base = ""
        apiKey = ""
    }

    private func persist() {
        defaults.set(base, forKey: Key.base)
        defaults.set(apiKey, forKey: Key.apiKey)
        defaults.set(apiMode.rawValue, forKey: Key.apiMode)
        defaults.set(model, forKey: Key.model)
        defaults.set(proxy, forKey: Key.proxy)
    }
}
