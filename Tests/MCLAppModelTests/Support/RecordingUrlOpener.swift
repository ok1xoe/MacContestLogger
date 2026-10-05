import Foundation
@testable import MCLAppModel

/// A browser that only records the pages it was asked to open.
final class RecordingUrlOpener: @unchecked Sendable {
    private let lock = NSLock()
    private var opened: [String] = []

    var urls: [String] {
        lock.withLock { opened }
    }

    var opener: UrlOpener {
        UrlOpener { [self] url in
            lock.withLock { opened.append(url) }
        }
    }
}
