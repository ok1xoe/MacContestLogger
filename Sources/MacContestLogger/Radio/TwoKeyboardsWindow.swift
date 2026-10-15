import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// N1MM Config → SO2R → „Two Keyboards" setup (Nastavení → SO2R → Dvě klávesnice…, `keyboards` 560×380): the option,
/// macOS Input Monitoring, the attached keyboards and which one drives entry window 1 / 2, and a test — the last
/// key's keyboard. While the window is open the keys are not moved between the entry windows.
struct TwoKeyboardsWindowView: View {
    static let id = "keyboards"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Dvě klávesnice") },
                        size: CGSize(width: 560, height: 380), minSize: CGSize(width: 440, height: 280),
                        appeared: { _ in host.keyboards?.beginTest() },
                        disappeared: { _ in host.keyboards?.endTest() },
                        content: { app, _ in
                            if let keyboards = host.keyboards {
                                TwoKeyboardsContent(app: app, keyboards: keyboards)
                            } else {
                                Text(verbatim: app.language.tr("Dvě klávesnice nejsou k dispozici"))
                                    .windowFont(13)
                            }
                        })
    }
}

private struct TwoKeyboardsContent: View {
    let app: AppModel
    let keyboards: TwoKeyboardModel

    /// macOS System Settings → Privacy & Security → Input Monitoring.
    private static let privacyUrl = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { keyboards.isEnabled }, set: { _ in keyboards.toggle() })) {
                Text(verbatim: language.tr("Dvě klávesnice — každá ovládá své zadávací okno"))
            }
            .windowFont(13)
            .accessibilityIdentifier("keyboards.enabled")
            accessRow(language)
            Divider()
            Text(verbatim: language.tr("Klávesnice"))
                .windowFont(13, weight: .semibold)
            if keyboards.devices.isEmpty {
                Text(verbatim: language.tr("Žádná klávesnice nenalezena"))
                    .windowFont(12)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(keyboards.devices, id: \.id) { device in
                        deviceRow(device, language: language)
                    }
                }
            }
            .accessibilityIdentifier("keyboards.list")
            Divider()
            Text(verbatim: testLine(language))
                .windowFont(12)
                .accessibilityIdentifier("keyboards.test")
            HStack {
                Button(language.tr("Obnovit seznam")) { keyboards.refreshDevices() }
                    .accessibilityIdentifier("keyboards.refresh")
                Spacer()
            }
            .windowFont(12)
        }
    }

    @ViewBuilder
    private func accessRow(_ language: LanguageModel) -> some View {
        HStack(spacing: 6) {
            switch keyboards.access {
            case .granted:
                Text(verbatim: language.tr("Sledování vstupu: povoleno"))
            case .denied:
                Text(verbatim: language.tr("Sledování vstupu: zakázáno — povol MacContestLogger v Nastavení systému"))
                    .foregroundStyle(.red)
            case .undetermined:
                Text(verbatim: language.tr("Sledování vstupu: zatím nepovoleno (macOS se zeptá po zapnutí)"))
            }
            Spacer()
            if keyboards.access != .granted {
                Button(language.tr("Otevřít Nastavení systému")) {
                    if let url = URL(string: Self.privacyUrl) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .accessibilityIdentifier("keyboards.privacy")
            }
        }
        .windowFont(12)
    }

    private func deviceRow(_ device: KeyboardDevice, language: LanguageModel) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: device.name).windowFont(12)
                Text(verbatim: device.id).windowFont(10, design: .monospaced).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(0..<2, id: \.self) { window in
                let saved: Bool = keyboards.savedKeyboard(window: window) == device.id
                SettingsChip(label: language.tr("Okno %s", .int(window + 1)), selected: saved) {
                    keyboards.assign(saved ? nil : device.id, window: window)
                }
            }
        }
    }

    private func testLine(_ language: LanguageModel) -> String {
        guard let id = keyboards.lastPressedDevice else {
            return language.tr("Test: stiskni klávesu na jedné z klávesnic")
        }
        let name: String = keyboards.name(of: id)
        guard let window = keyboards.window(of: id) else {
            return language.tr("Test: %s — nepřiřazena", .string(name))
        }
        return language.tr("Test: %s → okno %s", .string(name), .int(window + 1))
    }
}
