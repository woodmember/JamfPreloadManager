import Foundation

/// Appends a human-readable audit trail of preload record changes to a log file in
/// the user's standard log directory (`~/Library/Logs/Jamf Preload Manager/`).
///
/// Every ADD, MODIFY, and DELETE is recorded. MODIFY and DELETE capture the record's
/// previous values so an accidental change can be reversed by reading the log.
final class AuditLogger: @unchecked Sendable {
    static let shared = AuditLogger()

    private let lock = NSLock()
    private let formatter: DateFormatter

    /// The on-disk log file, or nil if the log directory could not be resolved.
    let fileURL: URL?

    init(fileURL: URL? = AuditLogger.defaultLogFileURL()) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        self.formatter = formatter
        self.fileURL = fileURL
    }

    static func defaultLogFileURL() -> URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }

        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(AppConstants.appName, isDirectory: true)
            .appendingPathComponent("PreloadActivity.log", isDirectory: false)
    }

    func logAdd(_ record: PreloadRecord) {
        write(operation: "ADD", serial: record.serialNumber, id: record.id, detail: "NEW: \(describe(record))")
    }

    func logModify(before: PreloadRecord?, after: PreloadRecord) {
        let beforeText = before.map(describe) ?? "(previous values unavailable)"
        write(
            operation: "MODIFY",
            serial: after.serialNumber,
            id: after.id,
            detail: "BEFORE: \(beforeText) | AFTER: \(describe(after))"
        )
    }

    func logDelete(_ record: PreloadRecord) {
        write(operation: "DELETE", serial: record.serialNumber, id: record.id, detail: "WAS: \(describe(record))")
    }

    /// Ensures the log file exists (creating the directory and header if needed) so it
    /// can be revealed in Finder even before the first change is recorded.
    @discardableResult
    func ensureLogFileExists() -> URL? {
        guard let fileURL else { return nil }
        lock.lock()
        defer { lock.unlock() }
        createIfNeeded(fileURL)
        return fileURL
    }

    // MARK: - Private

    private func describe(_ record: PreloadRecord) -> String {
        var parts = ["deviceType=\(record.deviceType)"]

        for key in record.standardValues.keys.sorted() {
            parts.append("\(key)=\(record.standardValues[key] ?? "")")
        }

        for name in record.extensionAttributes.keys.sorted() {
            parts.append("\(name)=\(record.extensionAttributes[name] ?? "")")
        }

        return parts.joined(separator: "; ")
    }

    private func write(operation: String, serial: String, id: Int, detail: String) {
        guard let fileURL else { return }

        lock.lock()
        defer { lock.unlock() }

        createIfNeeded(fileURL)

        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) | \(operation) | serial=\(serial) | id=\(id) | \(detail)\n"

        // Logging must never disrupt the operation, so failures are swallowed.
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// Creates the log directory and a header line if the file does not yet exist.
    /// Caller must hold `lock`.
    private func createIfNeeded(_ fileURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) == false else {
            return
        }

        let directory = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let header = """
        # \(AppConstants.appName) activity log
        # Records ADD / MODIFY / DELETE operations. BEFORE/WAS values are the record's
        # previous state, kept so an accidental change can be reversed.

        """
        try? Data(header.utf8).write(to: fileURL)
    }
}
