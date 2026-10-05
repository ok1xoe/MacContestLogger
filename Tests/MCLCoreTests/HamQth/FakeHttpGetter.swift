import Foundation
import os
@testable import MCLCore

/// A network stand-in for callbooks: returns scripted responses in order and records the request URLs
/// (like the generator's `FakeHttp` in a maintainer-only probe). After the script is exhausted it throws
/// `IOException("fronta prázdná")`. Blocks nothing.
final class FakeHttpGetter: HttpGetter {

    enum Step: Sendable {
        case response(Int, Data)
        case failure(String?)
    }

    private struct State {
        var script: [Step]
        var urls: [String] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(_ script: [Step]) {
        state = OSAllocatedUnfairLock(initialState: State(script: script))
    }

    /// A 200 response with a UTF-8 body text.
    static func ok(_ body: String) -> Step {
        .response(200, Data(body.utf8))
    }

    var urls: [String] {
        state.withLock { $0.urls }
    }

    var remaining: Int {
        state.withLock { $0.script.count }
    }

    func get(_ url: String) throws(HttpGetFailure) -> HttpGetResponse {
        let step: Step? = state.withLock { s in
            s.urls.append(url)
            return s.script.isEmpty ? nil : s.script.removeFirst()
        }
        switch step {
        case nil:
            throw HttpGetFailure("fronta prázdná")
        case .failure(let message):
            throw HttpGetFailure(message)
        case .response(let status, let body):
            return HttpGetResponse(status: status, body: body)
        }
    }
}
