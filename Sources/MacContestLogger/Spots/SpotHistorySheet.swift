import MCLAppModel
import MCLCore
import SwiftUI

/// N1MM „Show Telnet history" / „My call spot history": every spot of one call the cluster connections received in
/// this session (newest first): the UTC time, the frequency, the spotter, the comment and the connection.
struct SpotHistorySheet: View {
    let app: AppModel
    let call: String
    @Binding var fontSize: Int
    let close: () -> Void

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm'Z'"
        return formatter
    }()

    var body: some View {
        let language: LanguageModel = app.language
        let entries: [SpotHistory.Entry] = app.dxCluster.history(of: call).reversed()
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $fontSize, language: language) {
                Text(verbatim: language.tr("Historie spotů %s", .string(call))).windowFont(15, weight: .semibold)
            }
            if entries.isEmpty {
                Text(verbatim: language.tr("Žádný spot této volačky v tomto sezení."))
                    .windowFont(12)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        let text: String = row(entry)
                        Text(verbatim: text)
                            .windowFont(12, design: .monospaced)
                            .textSelection(.enabled)
                            .accessibilityLabel(text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DialogButtonRow {
                Button(language.tr("Zavřít")) { close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 620, height: 420)
        .environment(\.windowFontSize, fontSize)
    }

    private func row(_ entry: SpotHistory.Entry) -> String {
        let freq: String = FrequencyText.formatHz(Int64(entry.spot.freqHz))
        var text: String = Self.time.string(from: entry.at) + "  " + freq.padding(toLength: 10, withPad: " ",
                                                                                   startingAt: 0)
        text += "  " + entry.spot.spotter.padding(toLength: 10, withPad: " ", startingAt: 0) + "  " + entry.spot.comment
        if !entry.source.isEmpty {
            text += "  [" + entry.source + "]"
        }
        return text
    }
}
