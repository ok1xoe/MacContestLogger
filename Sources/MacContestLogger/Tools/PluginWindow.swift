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
                        content: { app, _ in PluginWindowContent(app: app, key: key) })
    }
}

private struct PluginWindowContent: View {
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
            }
            if let parsed, let content = session?.contents[parsed.window] {
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
                    .accessibilityLabel(Text(verbatim: label ?? ""))
            }
        case .tabs(let id, let tabs):
            PluginTabsView(id: id, tabs: tabs, actions: actions)
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
