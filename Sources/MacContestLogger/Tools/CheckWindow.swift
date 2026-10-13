import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The N1MM+ Check window (`check`): side-by-side panes of the log, `master.scp`, the spotted calls, the call history,
/// the exchange values and the reverse call history lookup for the call typed in the active entry window. The
/// characters of a call are coloured against the typed text (green = completes it, red = differs), an exact match is
/// bold italic. A click takes the call (or the exchange value); the right-click menu hides panes, sets their width,
/// the Alt+Y order and the other options.
struct CheckWindowView: View {
    static let id = "check"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Check") },
                        size: CGSize(width: 820, height: 300), minSize: CGSize(width: 360, height: 160),
                        appeared: { $0.check.open() }, disappeared: { $0.check.close() },
                        content: { app, _ in
            CheckContent(app: app)
        })
    }
}

private struct CheckContent: View {
    let app: AppModel

    var body: some View {
        let check: CheckModel = app.check
        let panes: [CheckPane] = check.visiblePanes
        let settings: CheckSettings = check.settings
        GeometryReader { proxy in
            let total: Int = max(1, panes.reduce(0) { $0 + settings.weight($1) })
            let spacing: CGFloat = 6
            let available: CGFloat = max(0, proxy.size.width - spacing * CGFloat(max(0, panes.count - 1)))
            HStack(alignment: .top, spacing: spacing) {
                ForEach(panes, id: \.self) { pane in
                    CheckPaneView(app: app, pane: pane)
                        .frame(width: available * CGFloat(settings.weight(pane)) / CGFloat(total))
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .contextMenu { CheckMenu(app: app, pane: nil) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: app.language.tr("Check")))
    }
}

private struct CheckPaneView: View {
    let app: AppModel
    let pane: CheckPane

    var body: some View {
        let check: CheckModel = app.check
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: header(check, language))
                .windowFont(12, weight: .bold)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.15))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    rows(check)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .contextMenu { CheckMenu(app: app, pane: pane) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: language.tr(pane.caption)))
    }

    private func header(_ check: CheckModel, _ language: LanguageModel) -> String {
        let caption: String = language.tr(pane.caption)
        switch pane {
        case .exchange:
            return check.exchangeField.map { caption + " " + $0 } ?? caption
        case .reverse:
            return caption + " (" + String(check.reverse.count) + ")"
        default:
            guard let found = check.panes.first(where: { $0.pane == pane }) else { return caption }
            return caption + " (" + String(found.matches.count) + "/" + String(found.total) + ")"
        }
    }

    @ViewBuilder
    private func rows(_ check: CheckModel) -> some View {
        switch pane {
        case .exchange:
            ForEach(Array(check.exchangeValues.enumerated()), id: \.offset) { _, value in
                Button {
                    takeExchange(value.key)
                } label: {
                    Text(verbatim: value.label.map { value.key + "  " + $0 } ?? value.key)
                        .windowFont(13, design: .monospaced)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        case .reverse:
            ForEach(Array(check.reverse.enumerated()), id: \.offset) { _, call in
                Button {
                    take(call)
                } label: {
                    Text(verbatim: call)
                        .windowFont(13, design: .monospaced)
                        .foregroundStyle(Color(nsColor: DomainColors.primary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        default:
            let matches: [CheckMatcher.Match] = check.panes.first(where: { $0.pane == pane })?.matches ?? []
            ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                Button {
                    take(match.call)
                } label: {
                    CheckCallText(match: match)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: AccessibilityText.checkMatch(
                    match.call, exact: match.isExact, translator: app.language.translator)))
            }
        }
    }

    private func take(_ call: String) {
        guard let entry = app.check.target() else { return }
        entry.takeCall(call)
    }

    private func takeExchange(_ value: String) {
        guard let entry = app.check.target(), let field = app.check.exchangeField else { return }
        entry.editContestField(field, value)
    }
}

/// A call with N1MM's character colours: typed characters plain, completing ones green, differing ones red; an exact
/// match bold italic.
struct CheckCallText: View {
    let match: CheckMatcher.Match

    var body: some View {
        match.segments.reduce(Text(verbatim: "")) { text, segment in
            text + Text(verbatim: segment.text).foregroundColor(color(segment.mark))
        }
        .windowFont(13, weight: match.isExact ? .bold : .regular, design: .monospaced)
        .italic(match.isExact)
        .lineLimit(1)
    }

    private func color(_ mark: CheckMatcher.Mark) -> Color {
        switch mark {
        case .same: return Color.primary
        case .extra: return Color(nsColor: SpotColors.multiMult)
        case .wrong: return Color(nsColor: SpotColors.oneMult)
        }
    }
}

/// The right-click menu (N1MM: Hide this pane, Proportional width this pane, the shown panes, Yank: configuration,
/// Yank: allow dupes, Sorting: Favor end-character differences, the reverse lookup and its threshold).
private struct CheckMenu: View {
    let app: AppModel
    let pane: CheckPane?

    var body: some View {
        let check: CheckModel = app.check
        let language: LanguageModel = app.language
        let settings: CheckSettings = check.settings
        if let pane {
            Button(language.tr("Skrýt tento panel")) {
                check.update { $0.hidden.insert(pane) }
            }
            Menu(language.tr("Proporcionální šířka tohoto panelu")) {
                ForEach(1...4, id: \.self) { weight in
                    Toggle(String(weight) + "×", isOn: Binding(
                        get: { settings.weight(pane) == weight },
                        set: { _ in check.update { $0.weights[pane] = weight } }))
                }
            }
            Divider()
        }
        Menu(language.tr("Zobrazené panely")) {
            ForEach(CheckPane.allCases, id: \.self) { item in
                Toggle(language.tr(item.caption), isOn: Binding(
                    get: { !settings.hidden.contains(item) },
                    set: { shown in check.update { if shown { $0.hidden.remove(item) } else { $0.hidden.insert(item) } } }))
            }
        }
        Menu(language.tr("Alt+Y: pořadí panelů")) {
            ForEach(Array(settings.yankOrder.enumerated()), id: \.offset) { index, item in
                Button(String(index + 1) + ". " + language.tr(item.caption)) {
                    check.update { $0.moveInYankOrder(item, by: -1) }
                }
                .disabled(index == 0)
            }
        }
        Toggle(language.tr("Alt+Y: i duplicitní volačky"), isOn: Binding(
            get: { settings.yankAllowsDupes },
            set: { on in check.update { $0.yankAllowsDupes = on } }))
        Toggle(language.tr("Řazení: upřednostnit rozdíly na konci volačky"), isOn: Binding(
            get: { settings.favorEnd },
            set: { on in check.update { $0.favorEnd = on } }))
        Menu(language.tr("Telnet: volačka od počtu spotů")) {
            ForEach(1...5, id: \.self) { count in
                Toggle(String(count), isOn: Binding(
                    get: { settings.telnetMinSpots == count },
                    set: { _ in check.update { $0.telnetMinSpots = count } }))
            }
        }
        Divider()
        Toggle(language.tr("Zpětné hledání v call history a deníku"), isOn: Binding(
            get: { settings.reverseEnabled },
            set: { on in check.update { $0.reverseEnabled = on } }))
        Menu(language.tr("Práh zpětného hledání (znaků)")) {
            ForEach(1...5, id: \.self) { count in
                Toggle(String(count), isOn: Binding(
                    get: { settings.reverseThreshold == count },
                    set: { _ in check.update { $0.reverseThreshold = count } }))
            }
        }
        .disabled(!settings.reverseEnabled)
        Toggle(language.tr("Zpětné hledání: shoda od prvního znaku"), isOn: Binding(
            get: { settings.reverseFromStart },
            set: { on in check.update { $0.reverseFromStart = on } }))
        .disabled(!settings.reverseEnabled)
    }
}

/// N1MM's ✓ / ? at the end of the call field: a check in the multiplier colour (green double, red single, blue
/// workable, grey dupe) when a Check source has the exact call, a `?` when none has it (View → „Zobrazovat ? u
/// neznámých volaček").
struct CallMarkView: View {
    let app: AppModel
    let entry: EntryModel

    var body: some View {
        let mark: CheckModel.CallMark = app.check.mark(for: entry)
        let language: LanguageModel = app.language
        switch mark {
        case .none:
            EmptyView()
        case .matched(let key):
            Text(verbatim: "✓")
                .windowFont(16, weight: .bold)
                .foregroundStyle(Color(nsColor: SpotColors.color(key)))
                .padding(.trailing, 6)
                .accessibilityLabel(Text(verbatim: language.tr("Volačka je ve zdrojích Check")))
                .accessibilityIdentifier("entry.callMark")
        case .unmatched:
            Text(verbatim: "?")
                .windowFont(16, weight: .bold)
                .foregroundStyle(Color(nsColor: SpotColors.oneMult))
                .padding(.trailing, 6)
                .accessibilityLabel(Text(verbatim: language.tr("Volačka není v žádném zdroji Check")))
                .accessibilityIdentifier("entry.callMark")
        }
    }
}
