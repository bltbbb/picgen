import Foundation

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
        static let model = "model"
        static let proxy = "proxy"
    }

    @Published var base: String { didSet { persist() } }
    @Published var apiKey: String { didSet { persist() } }
    @Published var model: String { didSet { persist() } }
    @Published var proxy: String { didSet { persist() } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        base = d.string(forKey: Key.base) ?? ""
        apiKey = d.string(forKey: Key.apiKey) ?? ""
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
        defaults.set(model, forKey: Key.model)
        defaults.set(proxy, forKey: Key.proxy)
    }
}
