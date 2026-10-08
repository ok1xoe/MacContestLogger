import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// A window of a window plugin (`plugin:<plugin>/<window>`): the shared tool-window frame (title, kept geometry,
/// the font stepper) around the content the plugin declared. Opening the window starts the plugin, the user's close
/// of its last window stops it. A plugin that ended or hangs leaves its last content under a banner with Restart.
struct PluginWindowView: View {
    /// The scene id of every plugin window (a window group keyed by the window key).
    static let sceneId = "plugin"

    let host: AppHost
    let key: String

    var body: some View {
        let manifest: PluginManifest.Window? = host.model?.pluginWindows.window(key)
        let size = CGSize(width: manifest?.width ?? 480, height: manifest?.height ?? 360)
        ToolWindowShell(host: host, id: key, title: { $0.pluginWindows.title(key) }, size: size,
                        minSize: CGSize(width: 240, height: 160),
                        appeared: { $0.pluginWindows.windowAppeared(key) },
                        closedByUser: { $0.pluginWindows.windowClosed(key) },
                        leading: { app in
                            IconButton(symbol: "rectangle.bottomhalf.inset.filled",
                                       label: app.language.tr("Ukotvit do hlavního okna")) {
                                app.pluginWindows.dock(key)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("pluginWindow.dock")
                        },
                        content: { app, _ in PluginWindowContent(app: app, key: key) })
    }
}

/// The content of a plugin window: the banner and the elements (also the inside of a docked panel).
struct PluginWindowContent: View {
    let app: AppModel
    let key: String

    var body: some View {
        let model: PluginWindowsModel = app.pluginWindows
        let parsed = PluginCatalog.parseWindowKey(key)
        let session: PluginSession? = parsed.flatMap { model.session($0.plugin) }
        VStack(alignment: .leading, spacing: 6) {
            if let banner = model.banner(key) {
                PluginBanner(text: banner, canRestart: session?.canRestart == true, language: app.language) {
                    if let plugin = parsed?.plugin {
                        model.restart(plugin)
                    }
                }
                if session?.phase == .awaitingConsent, let plugin = parsed?.plugin {
                    // Only the operator opens the consent sheet (it never pops up by itself mid-QSO).
                    Button {
                        model.requestConsent(plugin)
                    } label: {
                        Text(verbatim: app.language.tr("Rozhodnout o oprávněních…")).windowFont(12)
                    }
                    .accessibilityIdentifier("pluginWindow.consent")
                }
            }
            if let parsed, model.window(key)?.isWeb == true {
                if session?.phase == .running {
                    PluginWebView(app: app, key: key, title: model.title(key))
                        .id(model.webIdentity(key))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let parsed, let content = session?.contents[parsed.window] {
                ScrollView([.vertical]) {
                    PluginElementsView(elements: content.elements, actions: PluginActions(model: model, key: key))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else if session?.phase == .starting || session?.phase == .running {
                Text(verbatim: app.language.tr("Čekám na obsah od pluginu…"))
                    .windowFont(12)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: model.title(key)))
        .accessibilityIdentifier("pluginWindow")
    }
}

/// Why the plugin is not running, with Restart where a restart can help.
private struct PluginBanner: View {
    let text: String
    let canRestart: Bool
    let language: LanguageModel
    let restart: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            Text(verbatim: text)
                .windowFont(12, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if canRestart {
                Button(action: restart) {
                    Text(verbatim: language.tr("Restartovat"))
                        .windowFont(12)
                }
                .accessibilityLabel(Text(verbatim: language.tr("Restartovat plugin")))
                .accessibilityIdentifier("pluginWindow.restart")
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternaryLabelColor)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pluginWindow.banner")
    }
}

/// The interactions of one plugin window, handed to the model.
@MainActor
struct PluginActions {
    let model: PluginWindowsModel
    let key: String

    func click(_ target: String, row: Int? = nil, rowId: String? = nil, double: Bool = false) {
        model.click(key, target: target, row: row, rowId: rowId, double: double)
    }

    func toggle(_ target: String, _ value: Bool) {
        model.toggle(key, target: target, value: value)
    }

    func selectTab(_ target: String, _ tab: String) {
        model.selectTab(key, target: target, tab: tab)
    }

    func canvasClick(_ target: String, x: Double, y: Double) {
        model.canvasClick(key, target: target, x: x, y: y)
    }
}

/// A vertical stack of plugin elements (also the inside of a tab).
private struct PluginElementsView: View {
    let elements: [PluginUIElement]
    let actions: PluginActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                PluginElementView(element: element, actions: actions)
            }
        }
    }
}

private struct PluginElementView: View {
    let element: PluginUIElement
    let actions: PluginActions

    var body: some View {
        switch element {
        case .text(let text, let style):
            PluginStyledText(text: text, style: style, base: style == .title ? 15 : 13)
                .fixedSize(horizontal: false, vertical: true)
        case .table(let table):
            PluginTableView(table: table, actions: actions)
        case .list(let list):
            PluginListView(list: list, actions: actions)
        case .button(let id, let label, let enabled):
            Button {
                actions.click(id)
            } label: {
                Text(verbatim: label).windowFont(13)
            }
            .disabled(!enabled)
            .accessibilityLabel(Text(verbatim: label))
        case .toggle(let id, let label, let value):
            Toggle(isOn: Binding(get: { value }, set: { actions.toggle(id, $0) })) {
                Text(verbatim: label).windowFont(13)
            }
            .accessibilityLabel(Text(verbatim: label))
        case .progress(let value, let max, let label):
            VStack(alignment: .leading, spacing: 2) {
                if let label {
                    Text(verbatim: label).windowFont(12).foregroundStyle(.secondary)
                }
                ProgressView(value: value, total: max > 0 ? max : 1)
                    .accessibilityLabel(Text(verbatim: label ?? PluginProgressText.value(value, max: max)))
                    .accessibilityValue(Text(verbatim: PluginProgressText.value(value, max: max)))
            }
        case .tabs(let id, let tabs):
            PluginTabsView(id: id, tabs: tabs, actions: actions)
        case .canvas(let canvas):
            PluginCanvasView(canvas: canvas, actions: actions)
        }
    }
}

/// A text in a plugin style (the app's colours; the size follows the window's font stepper).
private struct PluginStyledText: View {
    let text: String
    let style: PluginUIStyle
    var base: Double = 13

    var body: some View {
        Text(verbatim: text)
            .windowFont(base, weight: style == .title ? .bold : .regular)
            .foregroundStyle(PluginStyleColor.color(style))
    }
}

/// The spoken value of a progress element (also its label when the plugin gave none): `3 / 10`.
enum PluginProgressText {
    static func value(_ value: Double, max: Double) -> String {
        func number(_ x: Double) -> String {
            x.rounded() == x && abs(x) < 1e15 ? String(Int64(x)) : String(format: "%.1f", x)
        }
        return number(value) + " / " + number(max)
    }
}

enum PluginStyleColor {
    static func color(_ style: PluginUIStyle) -> Color {
        switch style {
        case .normal, .title:
            return .primary
        case .muted:
            return .secondary
        case .warn:
            return Color(nsColor: .systemOrange)
        case .new:
            return Color(domain: DomainColors.primary)
        case .dupe:
            return Color(domain: DomainColors.dupe)
        case .mult:
            return Color(domain: DomainColors.multiplier)
        }
    }
}

private struct PluginTableView: View {
    let table: PluginUITable
    let actions: PluginActions

    var body: some View {
        let count: Int = max(table.columns.count, table.rows.map(\.cells.count).max() ?? 0)
        VStack(alignment: .leading, spacing: 0) {
            if !table.columns.isEmpty {
                row(table.columns.map { PluginUICell(text: $0.title, style: .muted) }, count: count, header: true)
                Divider()
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    tableRow(row, index: index, count: count)
                }
            }
        }
    }

    @ViewBuilder
    private func tableRow(_ source: PluginUIRow, index: Int, count: Int) -> some View {
        let cells: [PluginUICell] = source.cells.map { cell in
            cell.style == .normal ? PluginUICell(text: cell.text, style: source.style) : cell
        }
        let spoken: String = cells.map(\.text).joined(separator: ", ")
        if let id = table.id {
            row(cells, count: count, header: false)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { actions.click(id, row: index, rowId: source.id, double: true) }
                .onTapGesture { actions.click(id, row: index, rowId: source.id) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: spoken))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { actions.click(id, row: index, rowId: source.id) }
        } else {
            row(cells, count: count, header: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: spoken))
        }
    }

    private func row(_ cells: [PluginUICell], count: Int, header: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { column in
                let cell: PluginUICell = column < cells.count ? cells[column] : PluginUICell(text: "", style: .normal)
                let right: Bool = column < table.columns.count && table.columns[column].alignRight
                Text(verbatim: cell.text)
                    .windowFont(12, weight: header ? .semibold : .regular)
                    .foregroundStyle(PluginStyleColor.color(cell.style))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: right ? .trailing : .leading)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PluginListView: View {
    let list: PluginUIList
    let actions: PluginActions

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                if let id = list.id {
                    PluginStyledText(text: item.text, style: item.style)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { actions.click(id, row: index, rowId: item.id, double: true) }
                        .onTapGesture { actions.click(id, row: index, rowId: item.id) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { actions.click(id, row: index, rowId: item.id) }
                } else {
                    PluginStyledText(text: item.text, style: item.style)
                }
            }
        }
    }
}

/// The chosen tab of a tabs element (kept by the view; the plugin hears of it as `select`).
@MainActor
final class PluginTabsState: ObservableObject {
    @Published var selected: String?
}

private struct PluginTabsView: View {
    let id: String?
    let tabs: [PluginUITab]
    let actions: PluginActions
    @StateObject private var state = PluginTabsState()

    var body: some View {
        let current: String? = state.selected.flatMap { choice in tabs.contains { $0.id == choice } ? choice : nil }
            ?? tabs.first?.id
        VStack(alignment: .leading, spacing: 6) {
            Picker(selection: Binding(get: { current ?? "" }, set: { tab in
                state.selected = tab
                if let id {
                    actions.selectTab(id, tab)
                }
            })) {
                ForEach(tabs, id: \.id) { tab in
                    Text(verbatim: tab.title).tag(tab.id)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(Text(verbatim: tabs.map(\.title).joined(separator: ", ")))
            if let tab = tabs.first(where: { $0.id == current }) {
                PluginElementsView(elements: tab.elements, actions: actions)
            }
        }
    }
}

/// A canvas element: the shapes in the canvas's coordinates, scaled with the window's font size (so the drawing
/// grows with the text); a click on a canvas with an id sends its point in canvas coordinates.
private struct PluginCanvasView: View {
    let canvas: PluginUICanvas
    let actions: PluginActions
    @Environment(\.windowFontSize) private var windowSize

    /// What VoiceOver says for a canvas without its own label: its texts, else "drawing".
    private var fallbackLabel: String {
        let texts: [String] = canvas.shapes.compactMap { shape in
            if case .text(let text, _, _, _) = shape { return text }
            return nil
        }
        return texts.isEmpty ? "canvas" : texts.prefix(20).joined(separator: ", ")
    }

    var body: some View {
        let scale: Double = Double(windowSize) / Double(WindowFont.defaultSize)
        let shapes: [PluginUIShape] = canvas.shapes
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            for shape in shapes {
                PluginCanvasDrawing.draw(shape, in: &context)
            }
        }
        .frame(width: canvas.width * scale, height: canvas.height * scale)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            if let id = canvas.id {
                actions.canvasClick(id, x: location.x / scale, y: location.y / scale)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: canvas.label ?? fallbackLabel))
        .accessibilityAddTraits(canvas.id == nil ? [.isImage] : [.isImage, .isButton])
    }
}

enum PluginCanvasDrawing {
    static func draw(_ shape: PluginUIShape, in context: inout GraphicsContext) {
        switch shape {
        case .line(let from, let to, let style, let lineWidth):
            var path = Path()
            path.move(to: CGPoint(x: from.x, y: from.y))
            path.addLine(to: CGPoint(x: to.x, y: to.y))
            context.stroke(path, with: .color(PluginStyleColor.color(style)), lineWidth: lineWidth)
        case .rect(let x, let y, let width, let height, let style, let fill, let lineWidth):
            paint(Path(CGRect(x: x, y: y, width: width, height: height)), style: style, fill: fill,
                  lineWidth: lineWidth, in: &context)
        case .circle(let center, let radius, let style, let fill, let lineWidth):
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
            paint(Path(ellipseIn: rect), style: style, fill: fill, lineWidth: lineWidth, in: &context)
        case .path(let points, let closed, let style, let fill, let lineWidth):
            var path = Path()
            path.addLines(points.map { CGPoint(x: $0.x, y: $0.y) })
            if closed {
                path.closeSubpath()
            }
            paint(path, style: style, fill: fill, lineWidth: lineWidth, in: &context)
        case .text(let text, let point, let style, let size):
            context.draw(Text(verbatim: text).font(.system(size: size)).foregroundColor(PluginStyleColor.color(style)),
                         at: CGPoint(x: point.x, y: point.y), anchor: .topLeading)
        }
    }

    private static func paint(_ path: Path, style: PluginUIStyle, fill: Bool, lineWidth: Double,
                              in context: inout GraphicsContext) {
        if fill {
            context.fill(path, with: .color(PluginStyleColor.color(style)))
        } else {
            context.stroke(path, with: .color(PluginStyleColor.color(style)), lineWidth: lineWidth)
        }
    }
}

/// The plugin windows docked into the main window, under the entry panel: each with its title, Undock and Close.
struct PluginDockArea: View {
    let app: AppModel

    var body: some View {
        let model: PluginWindowsModel = app.pluginWindows
        let keys: [String] = model.dockedKeys
        if !keys.isEmpty {
            ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(verbatim: model.title(key))
                                .windowFont(12, weight: .semibold)
                            Spacer(minLength: 0)
                            IconButton(symbol: "macwindow", label: app.language.tr("Do samostatného okna")) {
                                model.undock(key)
                            }
                            IconButton(symbol: "xmark", label: app.language.tr("Zavřít panel pluginu")) {
                                model.closeDocked(key)
                            }
                        }
                        .buttonStyle(.borderless)
                        PluginWindowContent(app: app, key: key)
                            .frame(minHeight: 80, maxHeight: 260)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text(verbatim: model.title(key)))
                }
            }
            }
            // The main window sizes to its content: the dock gets a definite height, scrolling beyond it.
            .frame(height: min(420, CGFloat(keys.count) * 240))
            .padding(.horizontal, 8)
            .accessibilityIdentifier("pluginDock")
        }
    }
}

/// "Plugin X vysílá": shown in the entry window while a plugin's message or PTT is on the air.
struct PluginTransmitIndicator: View {
    let app: AppModel

    var body: some View {
        if app.rig.pluginPttUnconfirmed {
            let text: String = app.language.tr("PTT pluginu se nepodařilo uvolnit — zkontroluj vysílač!")
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon")
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .windowFont(13, weight: .bold)
                Spacer(minLength: 0)
                if !app.rig.pluginPttCannotConfirm.isEmpty {
                    Button {
                        app.rig.retryPluginRelease()
                    } label: {
                        Text(verbatim: app.language.tr("Uvolnit znovu")).windowFont(12)
                    }
                    .accessibilityLabel(Text(verbatim: app.language.tr("Znovu uvolnit PTT pluginu")))
                    .accessibilityIdentifier("pluginPttRetryRelease")
                }
            }
            .foregroundStyle(Color(domain: DomainColors.dupe))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(domain: DomainColors.dupe), lineWidth: 2))
            .padding(.horizontal, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pluginPttUnconfirmed")
        }
        if app.pluginWindows.transmissionsBlocked && app.pluginWindows.transmitting == nil {
            let text: String = app.language.tr("Vysílání pluginů zastaveno")
            HStack(spacing: 6) {
                Image(systemName: "pause.circle")
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .windowFont(13, weight: .semibold)
                Spacer(minLength: 0)
                Button {
                    app.pluginWindows.allowTransmissions()
                } label: {
                    Text(verbatim: app.language.tr("Povolit")).windowFont(12)
                }
                .accessibilityLabel(Text(verbatim: app.language.tr("Povolit vysílání pluginů")))
                .accessibilityIdentifier("pluginTransmissionsAllow")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            .padding(.horizontal, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: text))
        }
        if let name = app.pluginWindows.transmitting {
            let text: String = app.language.tr("Plugin %s vysílá", .string(name))
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .windowFont(13, weight: .bold)
                Spacer(minLength: 0)
                Button {
                    app.pluginWindows.stopTransmission()
                } label: {
                    Text(verbatim: app.language.tr("Zastavit (Esc)")).windowFont(12)
                }
                .accessibilityLabel(Text(verbatim: app.language.tr("Zastavit vysílání pluginu")))
            }
            .foregroundStyle(Color(nsColor: .systemOrange))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .systemOrange), lineWidth: 2))
            .padding(.horizontal, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: text))
            .accessibilityIdentifier("pluginTransmitting")
        }
    }
}
