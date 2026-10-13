import Foundation

/// N1MM „Output Main RX Window to Text File": the received text appended to
/// `<data>/ExportFiles/<MMddyyyy>DigitalInterface1Output.txt` (a new file each UTC day), written on its own serial
/// queue — never on the main thread.
final class DigitalRxLog: @unchecked Sendable {

    private let directory: URL
    private let queue = DispatchQueue(label: "mcl.digital-rx-log")

    init(dataDir: URL) {
        directory = dataDir.appendingPathComponent("ExportFiles")
    }

    /// The file for a day (UTC).
    func file(for date: Date) -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let name: String = String(format: "%02d%02d%04d", parts.month ?? 0, parts.day ?? 0, parts.year ?? 0)
            + "DigitalInterface1Output.txt"
        return directory.appendingPathComponent(name)
    }

    func append(_ text: String, at date: Date) {
        let url: URL = file(for: date)
        let directory: URL = self.directory
        queue.async {
            let data = Data(text.utf8)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Waits for the writes queued so far (tests).
    func flush() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { done.resume() }
        }
    }
}
