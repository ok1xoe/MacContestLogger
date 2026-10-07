import Foundation

/// The code-built default menu tree — a fallback and the source of default labels.
/// A pure factory (not a data type): the item order and exact texts must match,
/// because the user recognizes their menu by them — taken over from Java
/// item by item, without changing the order.
public enum DefaultMenu {

    private static let labels: [String: String] = [
        "file": "Soubor",
        "file.import": "Import",
        "file.export": "Export",
        "edit": "Úpravy",
        "edit.wipe": "Vymazat pole (nevratně)",
        "edit.wipeUndo": "Vymazat / vrátit pole",
        "edit.incrementNr": "Číslo ve výměně +1",
        "edit.note": "Poznámka k QSO",
        "edit.find": "Najít volačku v deníku",
        "edit.deleteLast": "Smazat poslední QSO",
        "tools": "Nástroje",
        "beacons.load": "Načíst soubor majáků…",
        "help": "Nápověda",
        "help.docs": "Dokumentace",
        "help.shortcuts": "Klávesové zkratky",
        "help.commands": "Textové příkazy",
        "help.report": "Nahlásit chybu…",
        "help.dataFolder": "Otevřít datovou složku",
        "settings.keys": "Klávesy…",
        "settings": "Nastavení",
        "settings.open": "Nastavení…",
        "settings.import": "Import QSO (ADIF/Cabrillo)…",
        "settings.export": "Export ADIF…",
        "settings.exportCabrillo": "Export Cabrillo…",
        "settings.downloadScp": "Stáhnout master.scp",
        "settings.exportEdi": "Export EDI (VKV)…",
        "settings.merge": "Sloučit deník…",
        "settings.print": "Tisk deníku…",
        "settings.profiles": "Profily nastavení…",
        "settings.exportOther": "Export CSV, text a souhrn…",
        "contest": "Závod",
        "contest.new": "Nový závod…",
        "contest.open": "Otevřít závod…",
        "contest.rescore": "Přepočítat skóre",
        "contest.postcontest": "Dodatečné zadání (papírový deník)",
        "contest.editor": "Editor definic…",
        "contest.record": "Nahrávat závod (zap / vyp)",
        "contest.updateDefinitions": "Aktualizovat definice z internetu",
        "contest.updateCallHistory": "Aktualizovat call history z deníku",
        "contest.none": "Žádný (volné logování)",
        "database": "Databáze",
        "database.new": "Nová databáze…",
        "database.open": "Otevřít databázi…",
        "window": "Okno",
        "window.log": "Přehled spojení",
        "window.catlog": "CAT log",
        "window.dxcluster": "DX Cluster",
        "window.bandmap": "Bandmapa",
        "window.hamqthlog": "HamQTH log",
        "window.skeds": "Skedy",
        "window.score": "Skóre",
        "window.movemults": "Přesun násobičů",
        "window.dupesheet": "Dupesheet",
        "window.waterfall": "Vodopád",
        "window.rotator": "Rotátor",
        "window.statistics": "Statistiky",
        "window.dxccmap": "Mapa DXCC a šedá linie",
        "window.qtc": "QTC (WAE)",
        "window.propagation": "Předpověď šíření",
        "window.bandnotes": "Poznámky k pásmům",
        "window.cwkeyboard": "CW z klávesnice",
        "window.cwreader": "CW Reader",
        "window.simulator": "Simulátor pileupu",
        "window.wsjtxdecodes": "WSJT-X dekódy",
        "window.netstatus": "Stav sítě",
        "window.chat": "Chat",
        "window.partner": "Partner",
        "buffer": "Nezařazené",
        "tab.hardware": "Hardware",
        "tab.function-keys": "Function Keys",
        "tab.keys": "Klávesy",
        "tab.digital-modes": "Digital Modes",
        "tab.other": "Other",
        "tab.winkey": "CW klíč",
        "tab.mode-control": "Mode Control",
        "tab.antennas": "Antennas",
        "tab.score-reporting": "Score Reporting",
        "tab.broadcast": "Broadcast Data",
        "tab.wsjt": "WSJT/JTDX",
        "tab.audio": "Audio",
        "tab.station": "Stanice",
        "tab.contest": "Závod",
        "tab.cluster": "Cluster",
        "tab.dxcluster": "DX Cluster",
        "tab.online_logs": "Online callbooks",
        "tab.bandplan": "Bandplán",
        "tab.digifreq": "Digi frekvence",
        "tab.map": "Mapa",
    ]

    /// Default label for the given `id`, or `nil` when the definition does not know it.
    public static func labelFor(_ id: String) -> String? {
        labels[id]
    }

    private static func leaf(_ id: String) -> MenuNode {
        MenuNode(id: id, label: nil, state: .enable, children: [])
    }

    private static func node(_ id: String, _ children: [MenuNode]) -> MenuNode {
        MenuNode(id: id, label: nil, state: .enable, children: children)
    }

    /// Default menu tree.
    public static func tree() -> MenuConfig {
        let settingsOpen = node("settings.open", [
            leaf("tab.hardware"), leaf("tab.function-keys"), leaf("tab.keys"), leaf("tab.digital-modes"),
            leaf("tab.other"), leaf("tab.winkey"), leaf("tab.mode-control"),
            leaf("tab.antennas"), leaf("tab.score-reporting"), leaf("tab.broadcast"),
            leaf("tab.wsjt"), leaf("tab.audio"), leaf("tab.station"),
            leaf("tab.contest"), leaf("tab.cluster"), leaf("tab.dxcluster"), leaf("tab.online_logs"),
            leaf("tab.bandplan"), leaf("tab.digifreq"), leaf("tab.map"),
        ])
        let file = node("file", [
            leaf("contest.new"), leaf("contest.open"), leaf("sep.file.1"),
            leaf("database.new"), leaf("database.open"), leaf("sep.file.2"),
            node("file.import", [leaf("settings.import"), leaf("settings.merge")]),
            node("file.export", [
                leaf("settings.export"), leaf("settings.exportCabrillo"), leaf("settings.exportEdi"),
                leaf("settings.exportOther"),
            ]),
            leaf("sep.file.3"), leaf("settings.print"),
        ])
        let edit = node("edit", [
            leaf("edit.wipe"), leaf("edit.wipeUndo"), leaf("edit.incrementNr"), leaf("edit.note"),
            leaf("edit.find"), leaf("edit.deleteLast"),
        ])
        let contest = node("contest", [leaf("contest.postcontest"), leaf("contest.record"), leaf("contest.none")])
        let tools = node("tools", [
            leaf("contest.rescore"), leaf("database.refillDxcc"), leaf("sep.tools.1"),
            leaf("settings.downloadScp"), leaf("contest.updateDefinitions"), leaf("database.updateClubLogDxcc"),
            leaf("contest.updateCallHistory"), leaf("beacons.load"), leaf("sep.tools.2"), leaf("contest.editor"),
        ])
        let settings = node("settings", [settingsOpen, leaf("settings.keys"), leaf("settings.profiles")])
        let help = node("help", [
            leaf("help.docs"), leaf("help.shortcuts"), leaf("help.commands"), leaf("sep.help.1"),
            leaf("help.report"), leaf("help.dataFolder"),
        ])
        let window = node("window", [
            leaf("window.log"),
            leaf("window.catlog"), leaf("window.dxcluster"), leaf("window.bandmap"),
            leaf("window.hamqthlog"), leaf("window.skeds"), leaf("window.score"), leaf("window.movemults"),
            leaf("window.dupesheet"), leaf("window.waterfall"), leaf("window.rotator"),
            leaf("window.statistics"), leaf("window.dxccmap"), leaf("window.qtc"), leaf("window.propagation"),
            leaf("window.bandnotes"), leaf("window.cwkeyboard"), leaf("window.cwreader"),
            leaf("window.simulator"), leaf("window.wsjtxdecodes"), leaf("window.netstatus"),
            leaf("window.chat"), leaf("window.partner"),
        ])
        let buffer = MenuNode(id: "buffer", label: nil, state: .hidden, children: [])

        var cfg = MenuConfig()
        cfg.menu = [file, edit, contest, tools, settings, window, help, buffer]
        return cfg
    }
}
