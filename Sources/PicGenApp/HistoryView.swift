import SwiftUI
import UIKit

struct ThumbView: View {
    @EnvironmentObject private var library: Library

    let record: GenRecord
    var height: CGFloat = 92

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(uiColor: .tertiarySystemFill)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: record.id) {
            if image == nil {
                image = library.image(for: record)
            }
        }
    }
}

struct HistorySheet: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss

    let onOpen: (GenRecord) -> Void
    let onReuse: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if library.records.isEmpty {
                    Text("还没有生成过图片")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(library.records) { record in
                            Button {
                                onOpen(record)
                            } label: {
                                HStack(spacing: 12) {
                                    ThumbView(record: record, height: 64)
                                        .frame(width: 64)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(record.prompt.isEmpty ? "(没有提示词)" : record.prompt)
                                            .font(.footnote)
                                            .lineLimit(2)
                                        Text("\(record.model) · \(secondsText(record.ms)) · \(dateText(record.createdAt))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    library.delete(record)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    onReuse(record.prompt)
                                } label: {
                                    Label("复用", systemImage: "arrow.up.left")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct ViewerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: ViewerItem
    let onReuse: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(item.meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !item.prompt.isEmpty {
                        Text(item.prompt)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 10) {
                        Button {
                            PhotoSaver.save(item.image) { _ in }
                        } label: {
                            Label("存相册", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)

                        ShareLink(item: Image(uiImage: item.image), preview: SharePreview("生成的图片", image: Image(uiImage: item.image))) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onReuse(item.prompt)
                        } label: {
                            Label("复用提示词", systemImage: "arrow.up.left")
                        }
                        .buttonStyle(.bordered)
                        .disabled(item.prompt.isEmpty)
                    }
                }
                .padding(16)
            }
            .navigationTitle("预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
