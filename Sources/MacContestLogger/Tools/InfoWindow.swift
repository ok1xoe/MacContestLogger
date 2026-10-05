import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `RateWindow` (`rate` 760×480, `RateWindow.kt:157-261`): the Info window. The station call and the sent
/// exchange on the left, the operator's call on the right of the stepper's row, the information lines about the typed
/// call, then the two rate graphs and the timers, then the program messages. The right button opens the context menu
/// of ~20 items (`InfoModel.menuEntries`); a goal file with band columns asks for the band in a sheet.
struct InfoWindowView: View {
    static let id = "rate"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Info") },
                        size: CGSize(width: 760, height: 480), minSize: CGSize(width: 560, height: 300),
                        appeared: { $0.info.open() }, disappeared: { $0.info.close() },
                        leading: { app in InfoHeaderView(header: app.info.header) },
                        content: { app, windowSize in
            InfoContent(app: app, windowSize: windowSize)
        })
    }
}

/// Kotlin `Header`: the station call (bold, 14), `Výměna: …` and, on the right, the operator's call in blue.
private struct InfoHeaderView: View {
    let header: InfoHeader

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: header.stationCall)
                .windowFont(14, weight: .bold, design: .monospaced)
                .accessibilityIdentifier("info.stationCall")
            if let exchange = header.exchangeText {
                Text(verbatim: exchange)
                    .windowFont(13, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("info.exchange")
            }
            Spacer(minLength: 8)
            Text(verbatim: header.operatorCall)
                .windowFont(14, weight: .bold, design: .monospaced)
                .foregroundStyle(InfoColors.operatorCall)
                .accessibilityIdentifier("info.operatorCall")
        }
        .padding(.trailing, 8)
    }
}

private struct InfoContent: View {
    let app: AppModel
    let windowSize: Int

    var body: some View {
        let info: InfoModel = app.info
        let settings: InfoWindowConfig = info.settings
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 0) {
            infoLines(info)
            HStack(alignment: .top, spacing: 20) {
                NearTermChart(rates: info.nearTerm,
                              summary: AccessibilityText.rateBarsValue(info.nearTerm, translator: language.translator))
                if let trend = info.trend {
                    TrendChart(trend: trend, windowSize: windowSize,
                               summary: AccessibilityText.trendValue(trend, translator: language.translator))
                }
                if settings.showTimers {
                    timers(info)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            if settings.showMessages {
                messages(info, language: language)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(info.menuEntries) { entry in
                Button(entry.title) { run(entry.action, info: info) }
            }
        }
        .sheet(isPresented: Binding(get: { info.pendingImport != nil }, set: { if !$0 { info.cancelImport() } })) {
            if let pending = info.pendingImport {
                GoalBandSheet(app: app, pending: pending)
            }
        }
    }

    private func infoLines(_ info: InfoModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(info.lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .windowFont(12, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 4)
        .accessibilityIdentifier("info.lines")
    }

    private func timer(_ cell: TimerCell) -> some View {
        InfoTimerView(cell: cell, stateText: AccessibilityText.timerState(cell.state,
                                                                          translator: app.language.translator))
    }

    private func timers(_ info: InfoModel) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            timer(info.offTime)
            if let onBand = info.onBand {
                timer(onBand)
            }
            if let changes = info.bandChanges {
                timer(changes)
            }
        }
        .accessibilityIdentifier("info.timers")
    }

    private func messages(_ info: InfoModel, language: LanguageModel) -> some View {
        let rows: [String] = info.messageRows
        return ZStack(alignment: .topLeading) {
            DigitalRxTextView(text: Self.text(rows, windowSize: windowSize),
                              accessibilityText: language.tr("Zprávy programu"),
                              inset: NSSize(width: 6, height: 3))
            if rows.isEmpty {
                Text(verbatim: language.tr("Zprávy programu (spoty vlastní značky) se objeví tady."))
                    .windowFont(12)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 66, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.12))
        .padding(.top, 6)
        .accessibilityIdentifier("info.messages")
    }

    /// The messages as one text, oldest first, newest at the bottom (the view scrolls to the end).
    static func text(_ rows: [String], windowSize: Int) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: CGFloat(WindowFont.size(12, windowSize: windowSize)),
                                               weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        return NSAttributedString(string: rows.joined(separator: "\n"), attributes: attributes)
    }

    /// The context menu's actions: the model does the work; the two that need a file ask a panel first.
    private func run(_ action: InfoMenuEntry.Action, info: InfoModel) {
        let language: LanguageModel = app.language
        switch action {
        case .importGoals:
            ToolFilePanels.open(message: language.tr("Import cílů")) { url in
                info.importGoals(url: url)
            }
        case .exportGoals:
            guard info.canExportGoals() else { return }
            ToolFilePanels.save(message: language.tr("Export cílů"), name: "goals.txt") { url in
                info.exportGoals(url: url)
            }
        default:
            info.perform(action)
        }
    }
}

/// Kotlin `GoalBandDialog`: the band to take a goal plan from, or all bands summed.
struct GoalBandSheet: View {
    let app: AppModel
    let pending: PendingGoalImport

    @StateObject private var session = SheetFontSession()

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $session.fontSize, language: language)
            Text(verbatim: language.tr("Import cílů — pásmo"))
                .windowFont(15, weight: .bold)
            Text(verbatim: language.tr("Soubor nese sloupce pásem. Vyber, ze kterého se má plán vzít."))
                .windowFont(13)
            Button(language.tr("Všechna pásma (součet)")) {
                app.info.chooseImportBand(nil)
            }
            .windowFont(13)
            .accessibilityIdentifier("goalBand.all")
            ForEach(pending.bands, id: \.self) { band in
                Button(band) {
                    app.info.chooseImportBand(band)
                }
                .windowFont(13)
                .accessibilityIdentifier("goalBand.\(band)")
            }
            HStack {
                Spacer()
                Button(language.tr("Zrušit")) {
                    app.info.cancelImport()
                }
                .windowFont(13)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 360)
        .environment(\.windowFontSize, session.fontSize)
    }
}

/// The stepper size of a sheet (a sheet is not a window of its own, so it keeps its own, not persisted).
@MainActor
final class SheetFontSession: ObservableObject {
    @Published var fontSize: Int = WindowFont.defaultSize
}
