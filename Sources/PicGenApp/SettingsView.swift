import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: Settings
    @Environment(\.dismiss) private var dismiss

    @State private var testing = false
    @State private var testResult: String?
    @State private var revealKey = false
    @State private var loadingModels = false
    @State private var modelNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Settings.exampleBase, text: $settings.base)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    HStack {
                        if revealKey {
                            TextField("填你的 API Key", text: $settings.apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("填你的 API Key", text: $settings.apiKey)
                        }
                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        TextField(Settings.exampleModel, text: $settings.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Menu {
                            ForEach(settings.modelChoices, id: \.self) { name in
                                Button {
                                    settings.model = name
                                } label: {
                                    if name == settings.model {
                                        Label(name, systemImage: "checkmark")
                                    } else {
                                        Text(name)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                    }

                    HStack(spacing: 8) {
                        Text(modelNote ?? "模型列表来自上游 /v1/models，也可以直接手输")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button {
                            Task { await loadModels() }
                        } label: {
                            if loadingModels {
                                ProgressView()
                            } else {
                                Text("拉取上游列表").font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(loadingModels || !settings.isConfigured)
                    }
                } header: {
                    Text("接口")
                } footer: {
                    Text("端点可以是 `https://你的中转`，也可以带 /v1；生图请求发到 `{端点}/v1/chat/completions`。填好点下面的「测试连接」验证。")
                }

                Section {
                    TextField("127.0.0.1:7890", text: $settings.proxy)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("只在手机直连不通时才需要填，走 HTTP 代理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("代理（可留空）")
                }

                Section {
                    Button {
                        test()
                    } label: {
                        HStack {
                            Text("测试连接（GET /v1/models）")
                            Spacer()
                            if testing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(testing || !settings.isConfigured)

                    if let testResult = testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("清空端点与 Key", role: .destructive) {
                        settings.clearCredentials()
                        testResult = nil
                    }
                } footer: {
                    Text("端点和 Key 只保存在本机 App 里，不会随代码上传；仓库里没有任何默认凭据。")
                }
            }
            .task {
                if settings.isConfigured && settings.upstreamModels.isEmpty {
                    await loadModels()
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func loadModels() async {
        guard settings.isConfigured else { return }
        await MainActor.run { loadingModels = true }
        let client = APIClient(
            base: settings.base,
            apiKey: settings.apiKey,
            model: settings.model,
            proxy: settings.proxy
        )
        do {
            let models = try await client.models()
            await MainActor.run {
                settings.upstreamModels = models
                if settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let first = models.first {
                    settings.model = first
                }
                modelNote = "上游 \(models.count) 个模型，已填进 ☰ 菜单"
                loadingModels = false
            }
        } catch {
            await MainActor.run {
                modelNote = "拉取失败：\(error.localizedDescription)"
                loadingModels = false
            }
        }
    }

    private func test() {
        testing = true
        testResult = nil
        let client = APIClient(
            base: settings.base,
            apiKey: settings.apiKey,
            model: settings.model,
            proxy: settings.proxy
        )
        Task {
            do {
                let models = try await client.models()
                await MainActor.run {
                    settings.upstreamModels = models
                    if settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let first = models.first {
                        settings.model = first
                    }
                    let head = models.prefix(3).joined(separator: ", ")
                    testResult = "OK · 拿到 \(models.count) 个模型：\(head)"
                    testing = false
                }
            } catch {
                await MainActor.run {
                    testResult = "失败：\(error.localizedDescription)"
                    testing = false
                }
            }
        }
    }
}
