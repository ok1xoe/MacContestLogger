import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `RotatorWindow` (`rotator` 360×460, `RotatorWindow.kt:38-93`, N1MM Rotor): the compass with the
/// rotator's needle and the ray to the typed call, the azimuth („—" when unknown), the poll status, the call's
/// azimuth, turning by the short / long path, to a typed azimuth (at most 3 digits), Stop, and the keys' hint.
struct RotatorWindowView: View {
    static let id = "rotator"

    let host: AppHost

    @StateObject private var session = WindowSession(id: RotatorWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 360, height: 460))
    /// The azimuth field (Kotlin `remember { mutableStateOf("") }`).
    @StateObject private var manual = DialogFormState()

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "Rotátor",
                                                binder: session.binder))
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 280, minHeight: 300)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let rotator: RotatorModel = app.rotator
        let call: String = KotlinStrings.trim(app.typedCall)
        let target: Int? = app.rig.azimuthTo(call)
        return VStack(alignment: .center, spacing: 8) {
            WindowTopBar(size: $session.fontSize, language: language)
            RotatorCompass(
                azimuth: rotator.azimuth, target: target,
                value: AccessibilityText.compassValue(azimuth: rotator.azimuth, target: target,
                                                      translator: language.translator),
                label: language.tr("Kompas rotátoru"))
            Text(verbatim: RadioWindowTexts.rotatorAzimuth(rotator.azimuth))
                .windowFont(28)
            Text(verbatim: rotator.statusText.text(language.translator, decimalSeparator: language.decimalSeparator))
                .windowFont(11)
                .foregroundStyle(.secondary)
            Text(verbatim: RadioWindowTexts.rotatorCallLine(call: call, target: target)
                .text(language.translator, decimalSeparator: language.decimalSeparator))
                .windowFont(14)
            HStack(spacing: 6) {
                Button {
                    rotator.turnToCall(call, longPath: false)
                } label: {
                    Text(verbatim: language.tr("Na volačku")).windowFont(14)
                }
                Button {
                    rotator.turnToCall(call, longPath: true)
                } label: {
                    Text(verbatim: language.tr("Dlouhá cesta")).windowFont(14)
                }
            }
            manualRow(app)
            Text(verbatim: language.tr("Alt+J na volačku, Ctrl+Alt+J dlouhou cestou, Alt+L stop"))
                .windowFont(11)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
    }

    /// The azimuth field (digits only, at most 3), „Natočit" and „Stop".
    private func manualRow(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let rotator: RotatorModel = app.rotator
        let manual: DialogFormState = self.manual
        let field = Binding<String>(get: { manual.text }, set: { manual.text = RadioWindowTexts.digits($0, limit: 3) })
        return HStack(alignment: .center, spacing: 6) {
            TextField(text: field) {
                Text(verbatim: "")
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .windowFont(14)
            .frame(width: 80)
            .accessibilityLabel(language.tr("Natočit"))
            Button {
                if let azimuth = RadioWindowTexts.rotatorFieldAzimuth(manual.text) {
                    rotator.turnTo(azimuth)
                }
            } label: {
                Text(verbatim: language.tr("Natočit")).windowFont(14)
            }
            Button {
                rotator.stop()
            } label: {
                Text(verbatim: "Stop").windowFont(14)
            }
        }
    }
}
