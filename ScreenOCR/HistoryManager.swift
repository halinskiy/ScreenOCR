import Foundation

struct CaptureEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date

    var preview: String {
        let truncated = text.prefix(60)
        let suffix = text.count > 60 ? "…" : ""
        return "\(truncated)\(suffix)"
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}

final class HistoryManager {
    static let shared = HistoryManager()
    private let key = "com.screenocr.captureHistory"
    private let maxEntries = 10

    private(set) var entries: [CaptureEntry] = []

    private init() {
        load()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = CaptureEntry(id: UUID(), text: trimmed, timestamp: Date())
        entries.insert(entry, at: 0)

        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CaptureEntry].self, from: data) else {
            return
        }
        entries = decoded
    }
}
