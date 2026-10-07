import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `MultiplierGridWindow` (`mult-<kind>` 980×620, `MultiplierGridWindow.kt:77-330`, N1MM multiplier grid): the
/// rows (prefix or key and six bands) flowed into columns by the visible height, the cells coloured worked / spotted /
/// spotted double multiplier, a tooltip with the spot on a spotted cell (a click tunes to it) and, for DXCC, the filter
/// of continents. One window per kind; its id in `openWindows` is `mult:<kind>`, its geometry id `mult-<kind>`.
struct MultGridWindowView: View {
    let host: AppHost
    let kind: String

    static func id(_ kind: String) -> String {
        "mult:" + kind
    }

    var body: some View {
        ToolWindowShell(host: host, id: Self.id(kind), geometryId: "mult-" + kind,
                        title: { $0.multGrid(kind: kind).title },
                        size: CGSize(width: 980, height: 620), minSize: CGSize(width: 420, height: 260),
                        appeared: { $0.multGrid(kind: kind).open() },
                        disappeared: { $0.multGrid(kind: kind).close() },
                        leading: { app in
            Headline(model: app.multGrid(kind: kind))
        },
                        content: { app, windowSize in
            MultGridContent(model: app.multGrid(kind: kind), windowSize: windowSize)
        })
    }
}

private struct Headline: View {
    let model: MultGridModel

    var body: some View {
        if model.contestActive && model.grid.available {
            Text(verbatim: model.headline)
                .windowFont(13, weight: .bold)
                .foregroundStyle(.mclPrimary)
                .lineLimit(1)
                .accessibilityIdentifier("mult.headline")
        }
    }
}

private struct MultGridContent: View {
    let model: MultGridModel
    let windowSize: Int

    var body: some View {
        if !model.contestActive {
            Text(verbatim: model.noContestText)
                .windowFont(13)
                .accessibilityIdentifier("mult.noContest")
            Spacer(minLength: 0)
        } else if !model.grid.available {
            Text(verbatim: model.unavailableText)
                .windowFont(13)
                .accessibilityIdentifier("mult.unavailable")
            Spacer(minLength: 0)
        } else {
            available
        }
    }

    private var available: some View {
        let metrics = MultGridLayout.Metrics(fontSp: max(windowSize - 1, 1))
        return VStack(alignment: .leading, spacing: 0) {
            legend
            Divider()
            GeometryReader { proxy in
                let columns: [[MultGridRow]] = MultGridLayout.columns(
                    rows: model.visibleRows, height: Float(proxy.size.height), metrics: metrics)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, rows in
                            GridColumnView(model: model, rows: rows, metrics: metrics)
                        }
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendItem(MultGridLayout.workedColor, "Worked")
            legendItem(MultGridLayout.spottedColor, "Spotted")
            legendItem(MultGridLayout.spottedDblColor, "Spotted (Dbl Mult)")
            if model.hasContinents {
                continentChecks
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("mult.legend")
    }

    private var continentChecks: some View {
        HStack(spacing: 4) {
            check("All", selected: model.selected.count == MultGridLayout.continents.count) {
                model.toggleAll()
            }
            ForEach(MultGridLayout.continents, id: \.self) { continent in
                check(continent, selected: model.selected.contains(continent)) {
                    model.toggle(continent: continent)
                }
            }
        }
        .padding(.leading, 12)
    }

    private func check(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(get: { selected }, set: { _ in action() })) {
            Text(verbatim: label).windowFont(11)
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("mult.continent.\(label)")
    }

    private func legendItem(_ color: UInt32, _ label: String) -> some View {
        HStack(spacing: 3) {
            Rectangle().fill(Color(argb: color)).frame(width: 12, height: 12)
            Text(verbatim: label).windowFont(11)
        }
    }
}

/// One column of the flow (Kotlin `GridColumn`): the band header and the rows.
private struct GridColumnView: View {
    let model: MultGridModel
    let rows: [MultGridRow]
    let metrics: MultGridLayout.Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: CGFloat(metrics.prefixW))
                ForEach(Array(MultGridLayout.bandHeaders.enumerated()), id: \.offset) { _, header in
                    Text(verbatim: header)
                        .font(.system(size: CGFloat(metrics.bandFontSp), weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: CGFloat(metrics.cell), alignment: .leading)
                }
            }
            .frame(height: CGFloat(metrics.headerH))
            ForEach(rows, id: \.key) { row in
                GridRowView(model: model, row: row, metrics: metrics)
            }
        }
    }
}

private struct GridRowView: View {
    let model: MultGridModel
    let row: MultGridRow
    let metrics: MultGridLayout.Metrics

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: MultGridLayout.label(row))
                .font(.system(size: CGFloat(metrics.fontSp), design: .monospaced))
                .lineLimit(1)
                .padding(.trailing, CGFloat(metrics.prefixGap))
                .frame(width: CGFloat(metrics.prefixW), alignment: .trailing)
            ForEach(Array(SpotAnalyzer.multGridBands.enumerated()), id: \.offset) { _, band in
                cell(band)
            }
        }
        .frame(height: CGFloat(metrics.rowH))
    }

    @ViewBuilder private func cell(_ band: Band) -> some View {
        let state: MultCell = MultGridLayout.cell(row, band: band)
        let size = CGFloat(metrics.square)
        Group {
            if let argb = MultGridLayout.color(state) {
                if let tip = model.tooltip(key: row.key, band: band) {
                    Rectangle().fill(Color(argb: argb))
                        .frame(width: size, height: size)
                        .help(tip)
                        .onTapGesture { model.tune(key: row.key, band: band) }
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "\(MultGridLayout.label(row)) \(band.adif)"))
                        .accessibilityValue(Text(verbatim: tip))
                        .accessibilityAddTraits(.isButton)
                } else {
                    Rectangle().fill(Color(argb: argb)).frame(width: size, height: size)
                }
            } else {
                Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 1).frame(width: size, height: size)
            }
        }
        .frame(width: CGFloat(metrics.cell), height: CGFloat(metrics.rowH), alignment: .leading)
    }
}
