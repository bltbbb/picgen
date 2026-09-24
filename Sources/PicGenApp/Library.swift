import Foundation
import UIKit

struct GenRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let file: String
    let prompt: String
    let model: String
    let createdAt: Date
    let ms: Int
    let bytes: Int
}

/// 本地图库：图片存 Documents/images/，索引存 Documents/history.json
final class Library: ObservableObject {
    @Published private(set) var records: [GenRecord] = []

    private let dir: URL
    private let indexURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("images", isDirectory: true)
        indexURL = docs.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    func url(for record: GenRecord) -> URL {
        dir.appendingPathComponent(record.file)
    }

    func image(for record: GenRecord) -> UIImage? {
        UIImage(contentsOfFile: url(for: record).path)
    }

    @discardableResult
    func add(image: UIImage, prompt: String, model: String, ms: Int) -> GenRecord? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let name = Self.stamp() + ".jpg"
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        } catch {
            return nil
        }
        let record = GenRecord(
            id: UUID(),
            file: name,
            prompt: prompt,
            model: model,
            createdAt: Date(),
            ms: ms,
            bytes: data.count
        )
        records.insert(record, at: 0)
        saveIndex()
        return record
    }

    func delete(_ record: GenRecord) {
        try? FileManager.default.removeItem(at: url(for: record))
        records.removeAll { $0.id == record.id }
        saveIndex()
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f.string(from: Date())
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([GenRecord].self, from: data) else { return }
        records = list
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
