import AppKit
import MCLAppModel
import Observation

/// Owns the app model for the scenes. The model is bootstrapped only after the resource check passed (the delegate
/// calls `start()` from `applicationDidFinishLaunching`); until then the windows show nothing.
@Observable @MainActor
final class AppHost {

    static let shared = AppHost()

    private(set) var model: AppModel?
    /// The quit decisions: one quit sequence, later ⌘Q presses are cancelled while it runs.
    @ObservationIgnored private var gate = TerminationGate()
    /// Set when the quit sequence starts: window closes from then on are not the user's.
    var isTerminating: Bool {
        gate.isTerminating
    }
    /// The quit milestones of the model (`AppModel.onQuitMilestone`), for the signal bridge.
    @ObservationIgnored var onQuitMilestone: (@MainActor () -> Void)?
    /// The quit runs without a pending `terminate:` (AppKit refused it, see `quitWithoutAppKit`).
    @ObservationIgnored private var endsWithoutAppKit = false
    /// The menu bar from `menu.json`; built once the model exists.
    @ObservationIgnored private var menuBuilder: MenuBuilder?

    /// Bootstraps the app model (Kotlin start-up, `AppModel.bootstrap`). A failure is reported and ends the app
    /// (Kotlin would crash).
    func start() {
        guard gate.phase == .notStarted else { return }
        gate.bootstrapStarted()
        Task {
            do {
                let app: AppModel = try await AppModel.bootstrap(.production())
                app.onQuitMilestone = { [weak self, weak app] in
                    QuitTrace.write("milestone transmitReleased=\(app?.transmitReleased ?? false)")
                    self?.onQuitMilestone?()
                }
                model = app
                if gate.bootstrapSucceeded() {
                    // ⌘Q arrived during the bootstrap: the regular quit sequence runs now.
                    await runQuitSequence(app)
                    return
                }
                let builder = MenuBuilder(app: app)
                builder.start()
                menuBuilder = builder
                QuitTrace.write("ready")
                #if DEBUG
                Self.smokeLanguageSwitch(app)
                Self.smokeQuit()
                #endif
            } catch {
                if gate.bootstrapFailed() {
                    // Nothing is open (the bootstrap failed); the pending quit simply proceeds.
                    endQuit()
                    return
                }
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Aplikaci nelze spustit."
                alert.informativeText = String(describing: error)
                alert.addButton(withTitle: "Ukončit")
                alert.runModal()
                AppQuit.request()
            }
        }
    }

    /// `applicationShouldTerminate`: the Kotlin quit sequence (`AppModel.shutdown`) runs once before the process ends;
    /// a further ⌘Q while it runs is cancelled (the first reply stays pending).
    func shouldTerminate() -> NSApplication.TerminateReply {
        let decision: TerminationGate.Decision = gate.requestTermination()
        QuitTrace.write("should terminate \(decision)")
        switch decision {
        case .terminateNow:
            return .terminateNow
        case .terminateCancel:
            return .terminateCancel
        case .terminateLater(let startShutdown):
            if startShutdown, let model {
                Task {
                    await runQuitSequence(model)
                }
            }
            return .terminateLater
        }
    }

    /// The quit when AppKit refused `terminate:` without asking the delegate — a sheet is attached to a window (the
    /// databases-directory choice, a prompt, a confirmation) or a modal session runs. A signal or the app's own quit
    /// request must still release the transmitter and end the process: the same quit sequence runs, and the process
    /// then ends without AppKit (the cleanup of `applicationWillTerminate`, then `exit(0)`).
    func quitWithoutAppKit() {
        let decision: TerminationGate.Decision = gate.requestTermination()
        QuitTrace.write("quit without AppKit \(decision)")
        switch decision {
        case .terminateNow:
            endsWithoutAppKit = true
            endQuit()
        case .terminateCancel:
            break
        case .terminateLater(let startShutdown):
            endsWithoutAppKit = true
            // Without a model yet the bootstrap runs the sequence when it ends (`bootstrapSucceeded`).
            if startShutdown, let model {
                Task {
                    await runQuitSequence(model)
                }
            }
        }
    }

    /// The Kotlin quit sequence, then the end of the process.
    private func runQuitSequence(_ model: AppModel) async {
        if QuitTrace.stallsQuit {
            // Debug check only: a quit wedged before the transmit release (never ends).
            QuitTrace.write("quit stalled")
            return
        }
        await model.shutdown()
        gate.shutdownFinished()
        QuitTrace.write("shutdown finished")
        endQuit()
    }

    /// The pending `terminateLater` is answered, or — for a quit AppKit refused — the process ends here.
    private func endQuit() {
        guard endsWithoutAppKit else {
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        QuitTrace.write("exit without AppKit")
        AppDelegate.cleanUpBeforeExit()
        exit(0)
    }

    #if DEBUG
    /// Quit-check hook of debug builds only: `MCL_SMOKE_QUIT=<seconds>` sends `terminate:` from a run-loop timer that
    /// many seconds after start — the context of ⌘Q / „Konec" (AppKit event handling, not a main-queue block) —
    /// without any input event.
    private static func smokeQuit() {
        guard let value = ProcessInfo.processInfo.environment["MCL_SMOKE_QUIT"], let seconds = Double(value) else {
            return
        }
        QuitTrace.write("smoke quit in \(value) s")
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: seconds)
    }

    /// Smoke-check hook of debug builds only: `MCL_SMOKE_LANGUAGE=<code>` switches the language two seconds after
    /// start, so a live language switch (menu bar and windows redrawn) can be observed without any input events.
    private static func smokeLanguageSwitch(_ app: AppModel) {
        guard let code = ProcessInfo.processInfo.environment["MCL_SMOKE_LANGUAGE"], !code.isEmpty else { return }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await app.language.switchTo(code)
        }
    }
    #endif
}
