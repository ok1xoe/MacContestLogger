import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The font size of the band map's sheets (the spot filter, the buttons' editor).
@MainActor
final class BandmapSheetState: ObservableObject {
    @Published var fontSize: Int = WindowFont.defaultSize
}

/// The Bandmap window's spot keys (Alt+M, Alt+D, Alt+Shift+D): a local `NSEvent` monitor — the application's own
/// events only — that hands key presses and releases to `BandmapModel.handleKey` while the Bandmap window is the key
/// window. Other keys pass on untouched. Removed when the window closes.
@MainActor
final class BandmapKeyMonitor: ObservableObject {
    private var token: Any?
    private weak var window: NSWindow?
    private var observer: NSObjectProtocol?
    private var model: BandmapModel?

    func install(window: NSWindow, model: BandmapModel) {
        guard self.window !== window || token == nil else { return }
        remove()
        self.window = window
        self.model = model
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let snapshot = KeyEventBridge.snapshot(event) else { return event }
            let consumed: Bool = MainActor.assumeIsolated {
                self?.handle(snapshot) ?? false
            }
            return consumed ? nil : event
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.remove() }
        }
    }

    func remove() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        window = nil
        model = nil
    }

    private func handle(_ snapshot: KeyEventSnapshot) -> Bool {
        guard let window, window.isKeyWindow, window.windowNumber == snapshot.windowNumber, let model else {
            return false
        }
        return model.handleButtonKey(snapshot.event) || model.handleKey(snapshot.event)
    }
}

/// Kotlin `BandmapWindow` (`bandmap` 460×640, `BandmapWindow.kt:75-360`): the radio, the tuned frequency (and the
/// TX frequency while split) with the zoom buttons and the window stepper top-right — one stepper for the window and
/// the spot labels (each step moves both) — then the band map. Without a tuned band only
/// the hint „Bandmapa — nalaď pásmo" shows.
struct BandmapWindowView: View {
    static let id = "bandmap"

    let host: AppHost

    @StateObject private var session = WindowSession(id: BandmapWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 460, height: 640))
    @StateObject private var keyMonitor = BandmapKeyMonitor()
    @StateObject private var sheets = BandmapSheetState()

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "Bandmapa",
                                                binder: session.binder))
                    .onAppear { app.bandmap.windowOpened() }
                    .background(WindowAccessor { window in
                        keyMonitor.install(window: window, model: app.bandmap)
                    })
            } else {
                Color.clear
            }
        }
        .frame(minWidth: BandmapLayout.minWidth(fontSize: session.fontSize), minHeight: 240)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let model: BandmapModel = app.bandmap
        let drawState: BandmapDrawState? = BandmapDrawState(model)
        return VStack(alignment: .leading, spacing: 0) {
            if let drawState {
                BandmapHeader(model: model, language: language, fontSize: $session.fontSize)
                BandmapTopBar(model: model, language: language)
                BandmapButtonGrid(model: model, language: language)
                BandmapView(model: model, language: language, state: drawState)
            } else {
                Text(verbatim: language.tr("Bandmapa — nalaď pásmo"))
                    .windowFont(14, weight: .semibold)
                    .foregroundStyle(.mclPrimary)
                    .trailingFontStepper(size: $session.fontSize, language: language,
                                         stepped: { model.setSpotFont(model.spotFont + $0) })
                    .padding(8)
                Spacer(minLength: 0)
            }
            RadioProblemBanner(rig: app.rig, language: language)
        }
        .environment(\.windowFontSize, session.fontSize)
        .sheet(isPresented: Binding(get: { model.showSpotFilter }, set: { model.showSpotFilter = $0 })) {
            SpotFilterSheet(app: app, fontSize: $sheets.fontSize, close: { model.showSpotFilter = false })
        }
        .sheet(isPresented: Binding(get: { model.editingButtons != nil },
                                    set: { if !$0 { model.editingButtons = nil } })) {
            BandmapButtonsEditor(model: model, language: language, fontSize: $sheets.fontSize)
        }
        .sheet(isPresented: Binding(get: { model.historyCall != nil }, set: { if !$0 { model.historyCall = nil } })) {
            SpotHistorySheet(app: app, call: model.historyCall ?? "", fontSize: $sheets.fontSize,
                             close: { model.historyCall = nil })
        }
    }
}

/// N1MM „Radio Problem" (band map, `RigConfig.timeoutSeconds`): the rig's connection was lost and has not come back
/// within the timeout. „Reset Radio" connects it again; × hides the alert.
private struct RadioProblemBanner: View {
    let rig: MCLAppModel.RigModel
    let language: LanguageModel

    var body: some View {
        if !rig.radioProblems.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                Text(verbatim: language.tr("Problém s rádiem: TRX neodpovídá"))
                    .windowFont(13, weight: .semibold)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button {
                    rig.resetRadios()
                } label: {
                    Text(verbatim: "Reset Radio")
                        .windowFont(12)
                }
                Button {
                    rig.dismissRadioProblem()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .accessibilityLabel(Text(verbatim: language.tr("Zavřít")))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.red)
        }
    }
}
