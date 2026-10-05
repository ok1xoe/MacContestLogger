import MCLAppModel
import MCLCore
import SwiftUI

/// The tabs of the Settings window as a sidebar (Kotlin `TabStrip`, `CW:142-187`): the visible specs of the current
/// menu in their order, a disabled one grey and not selectable (a deep link may still select it). A tab from
/// `menu.json` shows `tr(label)`, the fallback without a host the tab's own title (`App.kt:603`).
struct SettingsSidebar: View {
    let app: AppModel

    var body: some View {
        let settings: SettingsModel = app.settings
        let selection = Binding<ConfigurerTab?>(
            get: { settings.selected },
            set: { tab in
                guard let tab else { return }
                settings.select(tab)
            })
        List(selection: selection) {
            ForEach(settings.specs, id: \.tab) { spec in
                row(spec)
                    .tag(spec.tab)
                    .selectionDisabled(spec.state == .disable)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ spec: ConfigurerTabSpec) -> some View {
        let disabled: Bool = spec.state == .disable
        let label: String = spec.isLabelTranslated ? app.language.tr(spec.labelKey) : spec.labelKey
        return Text(verbatim: label)
            .windowFont(13, weight: spec.tab == app.settings.selected ? .semibold : .regular)
            .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .accessibilityLabel(Text(verbatim: label))
    }
}
