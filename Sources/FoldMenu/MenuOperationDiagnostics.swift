import Foundation

/// Main-actor callers only. Keeps bounded stages in memory; writes one file
/// only on failure. No screenshots, window titles, input contents or uploads.
final class MenuOperationDiagnostics {
    private struct Event: Encodable {
        let stage: String
        let elapsed: TimeInterval
        let detail: String
    }
    private struct Report: Encodable {
        let recordedAt: Date
        let os: String
        let itemID: String
        let events: [Event]
    }

    private let capacity: Int
    private let now: () -> TimeInterval
    private var startedAt: TimeInterval?
    private var itemID = ""
    private var events: [Event] = []

    init(capacity: Int = 32, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.capacity = min(64, max(1, capacity))
        self.now = now
    }

    func begin(itemID: String) {
        // Executable-path fallback IDs must not disclose personal paths.
        self.itemID = itemID.contains("/") ? "unidentified-item" : Self.bounded(itemID, bytes: 256)
        events.removeAll(keepingCapacity: true)
        startedAt = now()
        record("begin")
    }

    func record(_ stage: String, detail: String = "") {
        guard let startedAt else { return }
        events.append(Event(stage: Self.bounded(stage, bytes: 64),
                            elapsed: max(0, now() - startedAt),
                            detail: Self.bounded(detail, bytes: 512)))
        if events.count > capacity { events.removeFirst(events.count - capacity) }
    }

    func finish() { startedAt = nil }

    func saveFailure(_ error: Error, to file: URL) throws {
        guard startedAt != nil else { return }
        // Error descriptions can contain AX labels. Persist only a stable
        // category; numeric native error codes are recorded at their source.
        record("failure", detail: error is CancellationError ? "cancelled" : "operationFailed")
        finish()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Report(recordedAt: Date(), os: ProcessInfo.processInfo.operatingSystemVersionString,
                                             itemID: itemID, events: events))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    private static func bounded(_ text: String, bytes: Int) -> String {
        String(decoding: text.utf8.prefix(bytes), as: UTF8.self)
    }
}
