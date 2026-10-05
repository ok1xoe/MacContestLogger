import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `WorkedBeforeStrip` (`EP:1194-1199`, `EP:1426-1456`): where the call already is in the log. The current
/// band with a QSO is a dupe (error colours, outlined), a worked band has the tertiary colours, the others are muted.
struct WorkedBeforeStripView: View {
    let app: AppModel
    let panel: EntryPanel

    var body: some View {
        if let result = panel.suggestions.workedBefore, result.anyWorked {
            let current: String? = panel.entry.band?.adif
            let language: LanguageModel = app.language
            HStack(alignment: .center, spacing: 4) {
                Text(verbatim: EntrySuggestions.workedBeforeCaption(result)
                    .text(language.translator, decimalSeparator: language.decimalSeparator))
                    .windowFont(12, weight: .medium)
                    .foregroundStyle(.secondary)
                ForEach(Array(result.bands.enumerated()), id: \.offset) { _, status in
                    WorkedBandChip(status: status, here: status.band == current)
                }
            }
        }
    }
}

private struct WorkedBandChip: View {
    let status: WorkedBefore.BandStatus
    let here: Bool

    var body: some View {
        let colors: (background: NSColor, text: NSColor)? = chipColors
        Text(verbatim: EntrySuggestions.workedBeforeChip(status))
            .windowFont(12, weight: .medium, design: .monospaced)
            .foregroundStyle(colors.map { Color(nsColor: $0.text) } ?? Color.secondary.opacity(0.5))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(colors.map { Color(nsColor: $0.background) }
                ?? Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary, lineWidth: here ? 1 : 0))
    }

    private var chipColors: (background: NSColor, text: NSColor)? {
        if status.worked && here {
            return DomainColors.errorContainer
        }
        return status.worked ? DomainColors.tertiaryContainer : nil
    }
}

/// Kotlin's callbook row (`EP:1185-1192`): „Callbook: " and the record of the typed call — name, locator, zones —
/// when the callbook has one (the text is not translated in Kotlin).
struct CallbookLineView: View {
    let panel: EntryPanel

    var body: some View {
        if let line = panel.suggestions.callbookLine {
            Text(verbatim: line)
                .windowFont(11, weight: .medium)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("entry.callbook")
        }
    }
}

/// Kotlin `ScpSuggestions` (`EP:1458-1500`): Check partial on its own `SCP:` row under the call field, above N+1.
/// A call already worked on this band is red (a dupe), one worked elsewhere is muted, a spotted one is underlined;
/// the highlighted one is bold. A click takes it. The row is always reserved (its label shows even when empty), so
/// the layout does not jump. Settings → Contest can switch it off (`scpSuggestionsEnabled`): the view is then
/// not in the layout at all (Check partial also works from the log and spots without `master.scp`).
/// Set 2 pt (at stepper 12, scaled with it) larger than Kotlin's, like N+1.
struct ScpSuggestionsView: View {
    let app: AppModel
    let panel: EntryPanel
    @Environment(\.windowFontSize) private var size

    var body: some View {
        let suggestions: SuggestionsModel = panel.suggestions
        let partial: [PartialCheck.Suggestion] = suggestions.partial
        let language: LanguageModel = app.language
        HStack(alignment: .center, spacing: 6) {
            Text(verbatim: "SCP:")
                .windowFont(13, weight: .medium)
                .foregroundStyle(.secondary)
                .fixedSize()
            // One row; a suggestion that does not fit is not shown (the list is best-first, so the tail goes).
            ChipRowsLayout(rows: 1, rowHeight: WindowFont.size(22, windowSize: size),
                           maxIdealWidth: WindowFont.size(560, windowSize: size), spacing: 2) {
                ForEach(Array(partial.enumerated()), id: \.offset) { index, suggestion in
                    ScpSuggestionLabel(app: app, panel: panel, index: index, suggestion: suggestion,
                                       picked: index == suggestions.scpPick)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: WindowFont.size(22, windowSize: size))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: language.tr("Check partial (SCP)")))
    }
}

private struct ScpSuggestionLabel: View {
    let app: AppModel
    let panel: EntryPanel
    let index: Int
    let suggestion: PartialCheck.Suggestion
    let picked: Bool

    var body: some View {
        let spot: Bool = suggestion.source == .SPOT
        Button {
            panel.entry.takeSuggestion(index)
        } label: {
            Text(verbatim: suggestion.call)
                .windowFont(15, weight: picked ? .bold : .regular, design: .monospaced)
                .underline(spot)
                .lineLimit(1)
                .foregroundStyle(Color(domain: color(spot: spot)))
                .padding(.horizontal, 3)
                .background(picked ? Color(nsColor: .quaternaryLabelColor) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func color(spot: Bool) -> NSColor {
        let band: Band? = panel.entry.band
        if band != nil && app.logbook.isDupe(call: suggestion.call, band: band) {
            return DomainColors.dupe
        }
        if panel.suggestions.isLogged(suggestion.call) {
            return NSColor.secondaryLabelColor
        }
        return spot ? DomainColors.tertiary : DomainColors.primary
    }
}

/// The reverse call history lookup (`EP:1213-1234`): an empty call with a filled exchange lists the calls it fits.
/// A click takes the call and focuses the call field.
struct ReverseLookupView: View {
    let app: AppModel
    let panel: EntryPanel
    let focus: EntryFocusController

    var body: some View {
        let calls: [String] = panel.suggestions.reverse
        if !calls.isEmpty {
            CallRow(caption: "Call history:", calls: calls) { _ in DomainColors.primary } take: { call in
                panel.entry.takeCall(call)
                focus.focus(.call)
            }
        }
    }
}

/// N+1 (`EP:1235-1250`): calls one character off; the ones in the log are muted. A click takes the call. It stays
/// under the call field, below the `SCP:` row, on a row of its own that is always reserved with its label (so the
/// layout does not jump; Settings can switch it off, `nPlusOneEnabled`) and is set 2 pt (at stepper 12, scaled with it) larger than Kotlin's.
struct NPlusOneView: View {
    let app: AppModel
    let panel: EntryPanel
    @Environment(\.windowFontSize) private var size

    var body: some View {
        let suggestions: SuggestionsModel = panel.suggestions
        let calls: [String] = suggestions.nPlusOne
        ZStack(alignment: .leading) {
            Color.clear
            CallRow(caption: "N+1:", calls: calls, captionSize: 13, callSize: 15) { call in
                suggestions.isLogged(call) ? NSColor.secondaryLabelColor : DomainColors.secondary
            } take: { call in
                panel.entry.takeCall(call)
            }
        }
        .frame(height: WindowFont.size(22, windowSize: size))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: app.language.tr("N+1 (volačky o jeden znak vedle)")))
    }
}

/// A caption and clickable calls (the reverse lookup and N+1 rows; the captions are not translated in Kotlin).
private struct CallRow: View {
    let caption: String
    let calls: [String]
    var captionSize: Double = 11
    var callSize: Double = 13
    let color: @MainActor (String) -> NSColor
    let take: @MainActor (String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(verbatim: caption)
                .windowFont(captionSize, weight: .medium)
                .foregroundStyle(.secondary)
            ForEach(Array(calls.enumerated()), id: \.offset) { _, call in
                Button {
                    take(call)
                } label: {
                    Text(verbatim: call)
                        .windowFont(callSize, design: .monospaced)
                        .foregroundStyle(Color(domain: color(call)))
                        .padding(.horizontal, 3)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
