import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The look from Settings → Other (`App.kt:146-153`, `Theme.kt:94-112`).
@MainActor @Suite struct AppearanceModelTests {

    @Test func modeAndAccentFollowTheConfiguration() async throws {
        let app = try await TestApp.make()
        let config: ConfigModel = app.model.config
        let appearance: AppearanceModel = app.model.appearance
        #expect(appearance.appearance == .system)
        #expect(appearance.accent == .teal)

        let modes: [(String, AppearanceModel.Appearance)] = [
            ("LIGHT", .light), ("DARK", .dark), ("SYSTEM", .system), ("light", .system), ("", .system),
        ]
        for (mode, expected) in modes {
            config.config.themeMode = mode
            #expect(appearance.appearance == expected, "\(mode)")
            #expect(appearance.effectiveAppearance == expected, "\(mode)")
        }
        let accents: [(String, AppearanceModel.Accent)] = [
            ("TEAL", .teal), ("BLUE", .blue), ("ORANGE", .orange), ("CONTRAST", .contrast), ("PINK", .teal),
        ]
        for (accent, expected) in accents {
            config.config.themeAccent = accent
            #expect(appearance.accent == expected, "\(accent)")
            #expect(appearance.isContrast == (expected == .contrast), "\(accent)")
        }
    }

    /// Kotlin `colorSchemeFor(useDark || accent == "CONTRAST", accent)`: high contrast is dark whatever the mode.
    @Test func contrastForcesDark() async throws {
        let app = try await TestApp.make { config, _ in
            config.themeMode = "LIGHT"
            config.themeAccent = "CONTRAST"
        }
        let appearance: AppearanceModel = app.model.appearance
        #expect(appearance.appearance == .light)
        #expect(appearance.effectiveAppearance == .dark)
    }

    /// A commit changes the look at once (observers re-render).
    @Test func aCommitChangesTheLook() async throws {
        let harness = try await SettingsHarness.make()
        let appearance: AppearanceModel = harness.model.appearance
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.themeMode = "DARK"
        draft.themeAccent = "ORANGE"
        harness.settings.draft = draft
        final class Flag: @unchecked Sendable { var changed = false }
        let flag = Flag()
        withObservationTracking {
            _ = appearance.appearance
        } onChange: {
            flag.changed = true
        }

        #expect(await harness.settings.confirm())

        #expect(flag.changed)
        #expect(appearance.appearance == .dark)
        #expect(appearance.accent == .orange)
    }
}
