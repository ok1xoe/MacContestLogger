import AppKit
import CoreFoundation

/// Every quit the app starts itself (a termination signal, the main window closed, EXITNOW / the exit confirmation)
/// goes through `request()`, never through a direct `NSApp.terminate`.
///
/// Why: `applicationShouldTerminate` answers `.terminateLater` and AppKit then waits for the reply in a nested run loop
/// (modal panel mode) inside `terminate:`. The quit sequence (`AppModel.shutdown`) runs on the main actor, whose jobs
/// are blocks on the main dispatch queue. When `terminate:` is called from inside a main-queue block — a signal
/// source's handler, a main-queue notification observer, a model change made by a main-actor task — that block never
/// returns while the nested loop runs, and libdispatch does not drain the main queue re-entrantly: the quit sequence
/// never starts, the reply never comes, and the app hangs with the transmitter not released (seen with `kill -TERM`).
///
/// `request()` schedules `terminate:` as a run-loop block in the common modes, so it runs from the run loop itself,
/// outside any main-queue block; the nested loop then drains the main queue and the quit sequence runs. When AppKit
/// refuses the quit outright (a sheet is attached, a modal session runs) the quit sequence runs anyway
/// (`AppHost.quitWithoutAppKit`).
@MainActor
enum AppQuit {

    static func request() {
        performFromRunLoop {
            QuitTrace.write("terminate")
            NSApp.terminate(nil)
            // `terminate:` returns without asking the delegate when AppKit refuses to quit (a sheet attached to a
            // window, a modal session); the quit must not depend on that (a held PTT stays keyed while the app runs).
            if !AppHost.shared.isTerminating {
                AppHost.shared.quitWithoutAppKit()
            }
        }
    }

    /// Runs `body` on the main thread as a run-loop block in the common modes (default, modal panel, event tracking),
    /// never inside a main-queue block.
    static func performFromRunLoop(_ body: @escaping @MainActor () -> Void) {
        let loop: CFRunLoop = CFRunLoopGetMain()
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated {
                body()
            }
        }
        CFRunLoopWakeUp(loop)
    }
}
