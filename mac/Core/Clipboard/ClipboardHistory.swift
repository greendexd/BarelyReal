import Foundation

/// Persists the last 50 clipboard entries locally.
///
/// MVP implementation uses JSON under Application Support so the feature is usable without adding
/// SQLite dependencies yet. The public surface is intentionally storage-agnostic, so this can move
/// to SQLite later without touching clipboard sync code.
public final class ClipboardHistory {
    public static let maxEntries = 50

    private let url: URL
    private let maxEntries: Int

    public init(applicationSupportSubdir: String = "BarelyReal", filename: String = "clipboard-history.json", maxEntries: Int = ClipboardHistory.maxEntries) {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(applicationSupportSubdir, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(filename)
        self.maxEntries = maxEntries
    }

    public init(directory: URL, filename: String = "clipboard-history.json", maxEntries: Int = ClipboardHistory.maxEntries) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent(filename)
        self.maxEntries = maxEntries
    }

    public func append(_ entry: ClipboardEntry) {
        var entries = recent().filter { $0.contentHash != entry.contentHash }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save(entries)
    }

    public func recent() -> [ClipboardEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    private func save(_ entries: [ClipboardEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
