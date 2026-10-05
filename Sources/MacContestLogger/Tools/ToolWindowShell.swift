import AppKit
import MCLAppModel
import SwiftUI

/// The frame every info and tool window shares (Kotlin `Window(title = tr(…), state =
/// rememberPersistentWindowState(state, id, size))` with `WindowTopBar`): the translated title, the geometry kept in
/// `config.windowGeometry[geometryId]`, the font stepper top-right with the window's own content on its left, the
/// model's `open()` when the window appears and its `close()` when it goes, and the window's id leaving
/// `config.openWindows` when the user closes it.
///
/// The views inside are thin: they read the window's model and call its methods.
struct ToolWindowShell<Leading: View, Content: View>: View {
    let host: AppHost
    /// The id in `WindowsModel.openIds` (`rate`, `mult:dxcc`, `worldmap`).
    let id: String
    /// The Kotlin geometry id (`mult-dxcc` for the multiplier windows, else the same as `id`).
    let geometryId: String
    let title: (AppModel) -> String
    let size: CGSize
    let minSize: CGSize
    /// The window appeared (a model's `open()`).
    let appeared: (AppModel) -> Void
    /// The window went away: a model's `close()` (ticks and subscriptions stop), also when the app quits.
    let disappeared: (AppModel) -> Void
    /// The user closed the window: the model flag or the id that keeps it open is cleared.
    let closedByUser: (AppModel) -> Void
    @ViewBuilder let leading: (AppModel) -> Leading
    @ViewBuilder let content: (AppModel, Int) -> Content

    @StateObject private var session: WindowSession

    init(host: AppHost, id: String, geometryId: String? = nil, title: @escaping (AppModel) -> String,
         size: CGSize, minSize: CGSize = CGSize(width: 360, height: 200),
         appeared: @escaping (AppModel) -> Void = { _ in },
         disappeared: @escaping (AppModel) -> Void = { _ in },
         closedByUser: ((AppModel) -> Void)? = nil,
         @ViewBuilder leading: @escaping (AppModel) -> Leading,
         @ViewBuilder content: @escaping (AppModel, Int) -> Content) {
        self.host = host
        self.id = id
        self.geometryId = geometryId ?? id
        self.title = title
        self.size = size
        self.minSize = minSize
        self.appeared = appeared
        self.disappeared = disappeared
        self.closedByUser = closedByUser ?? { app in app.windows.setOpen(id, false) }
        self.leading = leading
        self.content = content
        _session = StateObject(wrappedValue: WindowSession(id: geometryId ?? id, persistSize: true, defaultSize: size))
    }

    var body: some View {
        Group {
            if let app = host.model {
                loaded(app)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: minSize.width, minHeight: minSize.height)
    }

    private func loaded(_ app: AppModel) -> some View {
        let binder: WindowGeometryBinder = session.binder
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: app.language) {
                leading(app)
            }
            content(app, session.fontSize)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.windowFontSize, session.fontSize)
        .navigationTitle(title(app))
        .onAppear {
            binder.setStore(app.geometry)
            appeared(app)
        }
        .onDisappear { disappeared(app) }
        .background(WindowAccessor { window in
            binder.isTerminating = { host.isTerminating }
            binder.onClose = { closedByUser(app) }
            binder.attach(window)
        })
    }
}

extension ToolWindowShell where Leading == EmptyView {
    init(host: AppHost, id: String, geometryId: String? = nil, title: @escaping (AppModel) -> String,
         size: CGSize, minSize: CGSize = CGSize(width: 360, height: 200),
         appeared: @escaping (AppModel) -> Void = { _ in },
         disappeared: @escaping (AppModel) -> Void = { _ in },
         closedByUser: ((AppModel) -> Void)? = nil,
         @ViewBuilder content: @escaping (AppModel, Int) -> Content) {
        self.init(host: host, id: id, geometryId: geometryId, title: title, size: size, minSize: minSize,
                  appeared: appeared, disappeared: disappeared, closedByUser: closedByUser,
                  leading: { _ in EmptyView() }, content: content)
    }
}

/// A caption over a group of a window (Kotlin `Panel`, `Text(title, fontSize = fs(), bold, onSurfaceVariant)`).
struct ToolCaption: View {
    let text: String
    var base: Double = 13

    var body: some View {
        Text(verbatim: text)
            .windowFont(base, weight: .bold)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// The grey explanation under a form (Kotlin `labelSmall` / `onSurfaceVariant`).
struct ToolHint: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .windowFont(11)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A selectable chip row (Kotlin `FilterChip`): used for the two-state switches of the windows.
struct ToolChips: View {
    struct Choice {
        let label: String
        let selected: Bool
        let identifier: String
        let action: () -> Void
    }

    let choices: [Choice]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                NetworkChip(label: choice.label, selected: choice.selected, identifier: choice.identifier,
                            action: choice.action)
            }
        }
    }
}

/// A labelled field of a form (Kotlin `Field(label) { KitTextField }`): the caption over the field.
struct ToolField<Field: View>: View {
    let label: String
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .windowFont(11)
                .foregroundStyle(.secondary)
            field()
        }
    }
}

/// The native file panels of the goal import and export (Kotlin `FileDialog`); a panel is not modal, the choice comes
/// back on the main actor.
@MainActor
enum ToolFilePanels {

    static func open(message: String, chosen: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = message
        run(panel, chosen: chosen)
    }

    static func save(message: String, name: String, chosen: @escaping @MainActor (URL) -> Void) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = message
        panel.nameFieldStringValue = name
        run(panel, chosen: chosen)
    }

    private static func run(_ panel: NSSavePanel, chosen: @escaping @MainActor (URL) -> Void) {
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { chosen(url) }
        }
    }
}

extension Color {
    /// A colour from `0xAARRGGBB` (the colour values of the core: `MultGridLayout`, `PropagationRows`, `MapPalette`).
    init(argb value: UInt32) {
        let alpha = Double((value >> 24) & 0xFF) / 255
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
