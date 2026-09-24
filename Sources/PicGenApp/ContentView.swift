import SwiftUI
import UIKit

struct ViewerItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let prompt: String
    let meta: String
}

struct ContentView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var library: Library

    @State private var prompt = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var infoText: String?

    @State private var result: UIImage?
    @State private var resultURL: URL?
    @State private var resultMeta = ""

    @State private var showSettings = false
    @State private var showHistory = false
    @State private var viewer: ViewerItem?
    @State private var didAutoOpenSettings = false

    private let presets = ["写实照片", "电影感光效", "日系插画", "3D 渲染", "油画质感"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !settings.isConfigured {
                        needsSetupCard
                    }
                    promptCard
                    statusSection
                    if let image = result {
                        resultCard(image)
                    }
                    historyCard
                }
                .padding(14)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear {
                if !settings.isConfigured && !didAutoOpenSettings {
                    didAutoOpenSettings = true
                    showSettings = true
                }
            }
            .navigationTitle("生图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { modelMenu }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showHistory) {
                HistorySheet(
                    onOpen: { record in
                        showHistory = false
                        open(record)
                    },
                    onReuse: { text in
                        prompt = text
                        showHistory = false
                    }
                )
            }
            .sheet(item: $viewer) { item in
                ViewerSheet(item: item) { text in
                    prompt = text
                    viewer = nil
                }
            }
        }
    }

    // MARK: - 顶部模型切换

    private var modelMenu: some View {
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
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text(shortModel).font(.caption)
            }
        }
    }

    private var shortModel: String {
        var name = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "未填模型" }
        if let range = name.range(of: "grok-imagine-") {
            name.removeSubrange(name.startIndex..<range.upperBound)
        }
        return name
    }

    // MARK: - 首次使用引导

    private var needsSetupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("先填接口和 Key").font(.headline)
            Text("App 不内置任何端点与凭据，需要你自己填：中转地址（如 \(Settings.exampleBase)）和自己的 API Key。填完再去首页生成。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                showSettings = true
            } label: {
                Label("去设置", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .card()
    }

    // MARK: - 提示词卡片

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("提示词").font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $prompt)
                .frame(minHeight: 112)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { item in
                        Button {
                            appendPreset(item)
                        } label: {
                            Text(item).font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
            }

            Button {
                generate()
            } label: {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView().tint(.white)
                    }
                    Text(busy ? "生成中…" : "生成图片").bold()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || !settings.isConfigured || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .card()
    }

    // MARK: - 状态提示

    @ViewBuilder
    private var statusSection: some View {
        if let errorText = errorText {
            statusCard(errorText, icon: "exclamationmark.triangle", color: .red)
        } else if let infoText = infoText {
            statusCard(infoText, icon: "info.circle", color: .secondary)
        }
    }

    private func statusCard(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .card()
    }

    // MARK: - 结果

    private func resultCard(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    viewer = ViewerItem(image: image, prompt: currentPrompt, meta: resultMeta)
                }

            HStack(spacing: 10) {
                Button {
                    PhotoSaver.save(image) { res in
                        switch res {
                        case .success:
                            errorText = nil
                            infoText = "已保存到相册"
                        case .failure(let error):
                            errorText = error.localizedDescription
                        }
                    }
                } label: {
                    Label("存相册", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                ShareLink(item: Image(uiImage: image), preview: SharePreview("生成的图片", image: Image(uiImage: image))) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button {
                    generate()
                } label: {
                    Label("再来", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(busy)

                Spacer(minLength: 0)
            }

            Text(resultMeta)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .card()
    }

    // MARK: - 历史

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("历史").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !library.records.isEmpty {
                    Button("全部 \(library.records.count)") { showHistory = true }
                        .font(.caption)
                }
            }

            if library.records.isEmpty {
                Text("还没有生成过图片").font(.footnote).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(library.records.prefix(12)) { record in
                        Button {
                            open(record)
                        } label: {
                            ThumbView(record: record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    // MARK: - 动作

    private var currentPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendPreset(_ text: String) {
        let trimmed = currentPrompt
        if trimmed.isEmpty {
            prompt = text + "："
        } else if prompt.contains(text) {
            return
        } else {
            prompt = trimmed + "，" + text
        }
    }

    private func open(_ record: GenRecord) {
        guard let image = library.image(for: record) else {
            errorText = "图片文件不在了：\(record.file)"
            return
        }
        viewer = ViewerItem(
            image: image,
            prompt: record.prompt,
            meta: "\(record.model) · \(secondsText(record.ms)) · \(bytesText(record.bytes)) · \(dateText(record.createdAt))"
        )
    }

    private func generate() {
        guard !busy else { return }
        guard settings.isConfigured else {
            errorText = "还没填接口地址或 API Key，点右上角 ⚙️ 去设置"
            return
        }
        let text = currentPrompt
        guard !text.isEmpty else { return }

        busy = true
        errorText = nil
        infoText = nil

        let client = APIClient(
            base: settings.base,
            apiKey: settings.apiKey,
            model: settings.model,
            proxy: settings.proxy
        )
        let model = settings.model

        Task {
            do {
                let output = try await client.generate(prompt: text)
                await MainActor.run {
                    result = output.image
                    resultURL = output.imageURL
                    resultMeta = "\(model) · \(secondsText(output.ms))"
                    infoText = "完成（\(secondsText(output.ms))）"
                    library.add(image: output.image, prompt: text, model: model, ms: output.ms)
                    busy = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    busy = false
                }
            }
        }
    }
}

extension View {
    func card() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

func secondsText(_ ms: Int) -> String {
    String(format: "%.1fs", Double(ms) / 1000)
}

func bytesText(_ bytes: Int) -> String {
    if bytes >= 1024 * 1024 {
        return String(format: "%.2f MB", Double(bytes) / 1048576)
    }
    return String(format: "%.0f KB", Double(bytes) / 1024)
}

func dateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: date)
}
