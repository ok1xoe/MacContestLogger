import MCLAppModel
import MCLCore
import SwiftUI

/// The spoken and shown names of the plugin permissions.
@MainActor
enum PluginPermissionText {
    static func label(_ permission: String, language: LanguageModel) -> String {
        switch permission {
        case "read": return language.tr("Čtení deníku, závodu, rádia a spotů")
        case "ui": return language.tr("Vlastní okna")
        case "entry": return language.tr("Zadávací okno: volačka, výměna, zapsání spojení")
        case "rig": return language.tr("Rádio: ladění, mód, split, RIT, VFO (bez vysílání)")
        case "spots": return language.tr("Spoty: přidat, odebrat, značka, blacklist")
        case "spots.send": return language.tr("Odesílat spoty do veřejné sítě DX clusteru")
        case "app.command": return language.tr("Textové příkazy volačkového pole (bez vysílání)")
        case "cat": return language.tr("Surové CAT příkazy rádiu (bez klíčování)")
        case "transmit": return language.tr("VYSÍLÁNÍ: CW, hlasové zprávy, F-klávesy a PTT")
        default: return permission
        }
    }
}

/// Settings → Plugins: every window plugin with the permissions it asks for, granted or not (changes apply at once
/// and are kept in `plugin-settings.json`), its key actions and the plugins directory reload.
struct PluginsTab: View {
    let app: AppModel

    var body: some View {
        let model: PluginWindowsModel = app.pluginWindows
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: language.tr("Pluginy")) {
                if !model.isActive {
                    SettingsText(language.tr("Pluginy jsou v tomto režimu vypnuté"), isError: true)
                }
                if model.catalog.packages.isEmpty {
                    SettingsCaption(language.tr("Žádné pluginy s okny"))
                }
                ForEach(model.catalog.packages, id: \.id) { package in
                    PluginGrantRow(app: app, package: package)
                    Divider()
                }
                Stepper(value: Binding(get: { model.settings.pttTimeoutSeconds },
                                       set: { model.setPttTimeout(seconds: $0) }), in: 5...300, step: 5) {
                    SettingsText(language.tr("PTT pluginu se samo uvolní po %s s",
                                             .int(model.settings.pttTimeoutSeconds)))
                }
                .accessibilityLabel(Text(verbatim: language.tr("PTT pluginu se samo uvolní po %s s",
                                                                .int(model.settings.pttTimeoutSeconds))))
                Stepper(value: Binding(get: { model.settings.messageLimitSeconds },
                                       set: { model.setMessageLimit(seconds: $0) }), in: 5...300, step: 5) {
                    SettingsText(language.tr("Zprávu pluginu přerušit po %s s",
                                             .int(model.settings.messageLimitSeconds)))
                }
                .accessibilityLabel(Text(verbatim: language.tr("Zprávu pluginu přerušit po %s s",
                                                                .int(model.settings.messageLimitSeconds))))
                Stepper(value: Binding(get: { model.settings.dutyPercent },
                                       set: { model.setDutyPercent($0) }), in: 10...100, step: 10) {
                    SettingsText(language.tr("Pluginy smí vysílat nejvýš %s procent z každých 5 minut",
                                             .int(model.settings.dutyPercent)))
                }
                .accessibilityLabel(Text(verbatim: language.tr("Pluginy smí vysílat nejvýš %s procent z každých 5 minut",
                                                                .int(model.settings.dutyPercent))))
                SettingsButton(language.tr("Načíst pluginy znovu")) {
                    model.refreshCatalog()
                }
                SettingsCaption(language.tr(
                    "Čtení a okna má každý plugin. Ostatní oprávnění platí hned po změně; plugin bez nich dostane chybu. Klávesy pro akce pluginů nastavíš v záložce Klávesy."))
            }
        }
        .onAppear { model.refreshCatalog() }
    }
}

private struct PluginGrantRow: View {
    let app: AppModel
    let package: PluginPackage

    var body: some View {
        let model: PluginWindowsModel = app.pluginWindows
        let language: LanguageModel = app.language
        let manifest: PluginManifest = package.manifest
        let granted: Set<String> = Set(model.settings.grants[PluginSettings.identity(manifest)] ?? [])
        VStack(alignment: .leading, spacing: 4) {
            SettingsText(manifest.name + (manifest.version.map { " " + $0 } ?? "") + " (" + package.id + ")",
                         weight: .semibold)
            ForEach(manifest.permissions.filter { PluginManifest.implicitPermissions.contains($0) }, id: \.self) {
                SettingsText("✓ " + PluginPermissionText.label($0, language: language), size: 12)
            }
            ForEach(manifest.permissionsNeedingGrant, id: \.self) { permission in
                SettingsCheckbox(label: PluginPermissionText.label(permission, language: language),
                                 isOn: Binding(get: { granted.contains(permission) }, set: { on in
                                     var next: Set<String> = granted
                                     if on { next.insert(permission) } else { next.remove(permission) }
                                     model.setGrants(package.id, Array(next))
                                 }),
                                 enabled: permission != "spots.send" || granted.contains("spots"))
            }
            if manifest.permissions.contains("spots.send") {
                SettingsCaption(language.tr(
                    "Odeslaný spot uvidí celá síť DX clusteru. Povol jen pluginu, kterému věříš."))
            }
            if manifest.permissions.contains("transmit") || manifest.permissions.contains("cat") {
                PluginTransmitWarning(language: language)
            }
            if model.settings.needsConsent(manifest) {
                SettingsButton(language.tr("Rozhodnout o oprávněních…")) {
                    model.requestConsent(package.id)
                }
            }
            if !manifest.unsupportedPermissions.isEmpty {
                SettingsText(language.tr("Plugin vyžaduje oprávnění, které tato verze neumí: %s",
                                         .string(manifest.unsupportedPermissions.joined(separator: ", "))),
                             size: 12, isError: true)
            }
            if !manifest.actions.isEmpty {
                SettingsCaption(language.tr("Akce pro klávesy: %s",
                                            .string(manifest.actions.map(\.title).joined(separator: ", "))))
            }
        }
    }
}

/// The first-use consent of a plugin that asks for permissions needing a grant: each one with a checkbox
/// (sending spots off by default), Allow selected / Deny all. Shown over the main window; it has its own font
/// stepper.
struct PluginConsentPresenter: ViewModifier {
    let app: AppModel

    func body(content: Content) -> some View {
        let model: PluginWindowsModel = app.pluginWindows
        content.sheet(isPresented: Binding(get: { model.consentRequest != nil }, set: { _ in })) {
            if let plugin = model.consentRequest, let package = model.catalog.package(plugin) {
                // A fresh sheet state for every plugin: no checkbox of one plugin carries over to the next.
                PluginConsentSheet(app: app, package: package, permissions: model.consentPermissions(plugin))
                    .id(plugin)
            }
        }
    }
}

private struct PluginConsentSheet: View {
    let app: AppModel
    let package: PluginPackage
    /// The undecided permissions the sheet asks about.
    let permissions: [String]
    @StateObject private var fontSize = ViewState<Int>(WindowFont.defaultSize)
    @StateObject private var chosen = ViewState<Set<String>?>(nil)

    var body: some View {
        let language: LanguageModel = app.language
        let manifest: PluginManifest = package.manifest
        let selection: Set<String> = chosen.value
            ?? Set(permissions.filter { !PluginManifest.offByDefault.contains($0) })
        VStack(alignment: .leading, spacing: 10) {
            WindowTopBar(size: $fontSize.value, language: language)
            Text(verbatim: language.tr("Plugin %s žádá o oprávnění", .string(manifest.name)))
                .windowFont(15, weight: .bold)
            ForEach(permissions, id: \.self) { permission in
                SettingsCheckbox(label: PluginPermissionText.label(permission, language: language),
                                 isOn: Binding(get: { selection.contains(permission) }, set: { on in
                                     var next: Set<String> = selection
                                     if on { next.insert(permission) } else { next.remove(permission) }
                                     chosen.value = next
                                 }),
                                 enabled: permission != "spots.send" || selection.contains("spots")
                                     || app.pluginWindows.effectivePermissions(package.id).contains("spots"))
            }
            if manifest.permissions.contains("spots.send") {
                SettingsCaption(language.tr(
                    "Odeslaný spot uvidí celá síť DX clusteru. Povol jen pluginu, kterému věříš."))
            }
            if permissions.contains("transmit") || permissions.contains("cat") {
                PluginTransmitWarning(language: language)
            }
            SettingsCaption(language.tr("Rozhodnutí můžeš kdykoli změnit v Nastavení → Pluginy."))
            HStack {
                Spacer(minLength: 0)
                SettingsButton(language.tr("Odmítnout vše")) {
                    app.pluginWindows.answerConsent(package.id, granted: [], shown: permissions)
                }
                SettingsButton(language.tr("Povolit vybrané")) {
                    app.pluginWindows.answerConsent(package.id, granted: Array(selection), shown: permissions)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 420)
        .environment(\.windowFontSize, fontSize.value)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pluginConsent")
    }
}

struct PluginActionRow {
    let plugin: PluginPackage
    let action: PluginManifest.Action

    var id: String {
        PluginSettings.actionKey(plugin: plugin.id, action: action.id)
    }
}

/// Keys → Plugins: every action of every plugin with its key (Change, None) and whether the key keeps its own
/// entry-window function. Applies at once (kept in `plugin-settings.json`).
struct PluginKeysGroup: View {
    let app: AppModel
    @EnvironmentObject private var keys: KeyCaptureMonitor
    @StateObject private var capturing = ViewState<String?>(nil)
    @StateObject private var hint = ViewState<String>("")

    var body: some View {
        let model: PluginWindowsModel = app.pluginWindows
        let language: LanguageModel = app.language
        let rows: [PluginActionRow] = model.catalog.packages.flatMap { package in
            package.manifest.actions.map { PluginActionRow(plugin: package, action: $0) }
        }
        if !rows.isEmpty {
            SettingsGroup(title: language.tr("Akce pluginů")) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                    ForEach(rows, id: \.id) { row in
                        let id: String = row.id
                        GridRow {
                            SettingsText("Plugin: " + row.plugin.manifest.name + " / " + row.action.title)
                            if capturing.value == id {
                                Text(verbatim: language.tr(SettingsTexts.capturePrompt))
                                    .windowFont(13)
                                    .foregroundStyle(.tint)
                            } else {
                                let conflict: String? = model.keyConflict(plugin: row.plugin.id, action: row.action.id)
                                SettingsText((model.settings.keys[id] ?? "—")
                                             + (conflict.map { " — " + language.tr("kolize s %s", .string($0)) } ?? ""),
                                             isError: conflict != nil)
                            }
                            SettingsButton(language.tr("Změnit"), borderless: true) {
                                capture(id, plugin: row.plugin.id, action: row.action.id)
                            }
                            .fixedSize()
                            SettingsButton(language.tr("Žádná"), borderless: true) {
                                model.bindKey(plugin: row.plugin.id, action: row.action.id, key: nil)
                            }
                            .fixedSize()
                            SettingsCheckbox(label: language.tr("Ponechat i původní funkci klávesy"),
                                             isOn: Binding(get: { model.settings.passThrough.contains(id) },
                                                           set: { model.setPassThrough(plugin: row.plugin.id,
                                                                                       action: row.action.id, $0) }))
                        }
                    }
                }
                if !hint.value.isEmpty {
                    SettingsText(hint.value, size: 12, isError: true)
                }
            }
        }
    }

    private func capture(_ id: String, plugin: String, action: String) {
        capturing.value = id
        keys.startCapture { result in
            switch result {
            case .cancelled:
                finish()
            case .ignored, .rejected:
                break
            case .accepted(let text):
                hint.value = app.pluginWindows.bindKey(plugin: plugin, action: action, key: text) ?? ""
                finish()
            }
        }
    }

    private func finish() {
        capturing.value = nil
        keys.stopCapture()
    }
}

/// The strong warning for `transmit` and `cat`.
struct PluginTransmitWarning: View {
    let language: LanguageModel

    var body: some View {
        SettingsText(language.tr(
            "Pozor: plugin s oprávněním k vysílání může klíčovat tvoji stanici. Esc, ukončení i odpojení rádia vysílání vždy zastaví a PTT se samo uvolní po nastavené době — povol jen pluginu, jehož kódu věříš."),
                     size: 12, weight: .semibold, isError: true)
    }
}
