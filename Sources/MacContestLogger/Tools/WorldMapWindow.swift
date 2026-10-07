import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `WorldMapWindow` (`worldmap` 900×520, `WorldMapWindow.kt:77-175`): the equirectangular world map centred on
/// the station, in two modes — the Maidenhead fields (the multipliers of a grid contest, coloured worked / spotted /
/// double, a click on a field tunes to its spot) or the DXCC entities as dots with the grey line. The window's saved id
/// is `worldmap-dxcc` when it was opened in the DXCC mode, else `worldmap`. Without outlines (`dxcc.geojson` missing)
/// the map is empty, nothing fails.
struct WorldMapWindowView: View {
    static let id = "worldmap"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Mapa") },
                        size: CGSize(width: 900, height: 520), minSize: CGSize(width: 420, height: 260),
                        appeared: { $0.worldMap.open() }, disappeared: { $0.worldMap.close() },
                        closedByUser: { $0.windows.setWorldMapOpen(false) },
                        content: { app, _ in WorldMapContent(app: app) })
    }
}

private struct WorldMapContent: View {
    let app: AppModel

    var body: some View {
        let model: WorldMapWindowModel = app.worldMap
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 6) {
            ToolChips(choices: [
                ToolChips.Choice(label: language.tr("Čtverce"), selected: !model.dxccMode,
                                 identifier: "worldmap.squares", action: { model.dxccMode = false }),
                ToolChips.Choice(label: language.tr("DXCC + šedá linie"), selected: model.dxccMode,
                                 identifier: "worldmap.dxcc", action: { model.dxccMode = true }),
            ])
            if model.needsContest {
                Text(verbatim: model.noContestText)
                    .windowFont(13)
                    .accessibilityIdentifier("worldmap.noContest")
                Spacer(minLength: 0)
            } else {
                Text(verbatim: model.title)
                    .windowFont(13, weight: .bold)
                    .foregroundStyle(.mclPrimary)
                    .accessibilityIdentifier("worldmap.title")
                WorldMapCanvas(scene: scene(model),
                               onSize: { size in
                                   model.setCanvas(width: Float(size.width), height: Float(size.height))
                               },
                               onTap: { point, size in
                                   model.tap(x: Float(point.x), y: Float(point.y), width: Int(size.width),
                                             height: Int(size.height))
                               },
                               summary: AccessibilityText.worldMapValue(
                                   dxccMode: model.dxccMode, fields: model.fieldStates.count, dots: model.dots.count,
                                   translator: language.translator))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func scene(_ model: WorldMapWindowModel) -> WorldMapScene {
        WorldMapScene(geo: model.geo, projection: model.projection, scheme: model.scheme,
                      political: model.political, dxccMode: model.dxccMode,
                      fieldStates: model.dxccMode ? [:] : model.fieldStates,
                      dots: model.dxccMode ? model.dots : [], night: model.night, nowMillis: model.nowMillis,
                      station: model.station, title: model.title)
    }
}
