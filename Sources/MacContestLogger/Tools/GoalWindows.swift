import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `GoalEditorWindow` (`goals` 420×560, `GoalWindows.kt:50-168`): the plan of QSOs per contest hour. Without a
/// running contest that has a start date only the explanation and „Zavřít" show. A save writes the goals to the config
/// and closes the window either way (Kotlin does).
struct GoalEditorWindowView: View {
    static let id = "goals"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Cíle závodu") },
                        size: CGSize(width: 420, height: 560), minSize: CGSize(width: 340, height: 300),
                        appeared: { $0.goals.openEditor() },
                        closedByUser: { $0.info.showGoalEditor = false },
                        content: { app, _ in GoalEditorContent(app: app) })
    }
}

private struct GoalEditorContent: View {
    let app: AppModel
    @Environment(\.windowFontSize) private var windowSize

    var body: some View {
        let goals: GoalsModel = app.goals
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 6) {
            if goals.needsContest {
                Text(verbatim: goals.noContestText)
                    .windowFont(13)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("goals.noContest")
                Button(language.tr("Zavřít")) { app.info.showGoalEditor = false }
                    .windowFont(13)
                    .padding(.top, 12)
            } else {
                Text(verbatim: goals.helpText)
                    .windowFont(11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                bulkFill(goals)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(goals.hours, id: \.self) { key in
                            hourRow(goals, key: key)
                        }
                    }
                }
                Divider()
                HStack {
                    Spacer()
                    Button(language.tr("Vymazat vše")) { goals.draft.clearAll() }
                    Button(language.tr("Zrušit")) { app.info.showGoalEditor = false }
                    Button(language.tr("Uložit")) {
                        Task { @MainActor in
                            _ = await goals.save()
                            app.info.showGoalEditor = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("goals.save")
                }
                .windowFont(13)
            }
        }
    }

    private func bulkFill(_ goals: GoalsModel) -> some View {
        HStack(spacing: 6) {
            TextField("", text: Binding(get: { goals.bulk.value }, set: { goals.bulk.setValue($0) }))
                .textFieldStyle(.roundedBorder)
                .windowFont(13)
                .frame(width: 64)
                .accessibilityLabel(Text(verbatim: "Vyplnit"))
                .accessibilityIdentifier("goals.bulkValue")
            Text(verbatim: "od").windowFont(11)
            HourPicker(hours: goals.hours, selection: Binding(get: { goals.bulk.fromKey },
                                                              set: { goals.bulk.fromKey = $0 }),
                       identifier: "goals.from")
            Text(verbatim: "do").windowFont(11)
            HourPicker(hours: goals.hours, selection: Binding(get: { goals.bulk.toKey },
                                                              set: { goals.bulk.toKey = $0 }),
                       identifier: "goals.to")
            Button("Vyplnit") { goals.applyBulk() }
                .windowFont(13)
                .accessibilityIdentifier("goals.apply")
        }
        .padding(.top, 8)
    }

    private func hourRow(_ goals: GoalsModel, key: Int32) -> some View {
        HStack {
            Text(verbatim: GoalEditing.hourLabel(key))
                .windowFont(12, design: .monospaced)
                .frame(width: WindowFont.size(120, windowSize: windowSize), alignment: .leading)
            TextField("", text: Binding(get: { goals.draft.text(for: key) },
                                        set: { goals.draft.setText($0, for: key) }))
                .textFieldStyle(.roundedBorder)
                .windowFont(12)
                .frame(width: 90)
                .accessibilityLabel(Text(verbatim: GoalEditing.hourLabel(key)))
        }
    }
}

/// Kotlin `HourPicker`: the hour of a range end as a menu.
private struct HourPicker: View {
    let hours: [Int32]
    @Binding var selection: Int32
    let identifier: String

    var body: some View {
        Picker(selection: $selection) {
            ForEach(hours, id: \.self) { key in
                Text(verbatim: GoalEditing.hourLabel(key)).tag(key)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .windowFont(11, design: .monospaced)
        .fixedSize()
        .accessibilityIdentifier(identifier)
    }
}

/// Kotlin `GoalFromLogWindow` (`goals-from-log` 560×460, `GoalWindows.kt:210-312`): the contests of an earlier log, the
/// goal of every hour = the number of QSOs made in it. A click on a contest imports and closes the window.
struct GoalFromLogWindowView: View {
    static let id = "goals-from-log"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Cíle z dřívějšího deníku") },
                        size: CGSize(width: 560, height: 460), minSize: CGSize(width: 400, height: 260),
                        appeared: { app in Task { @MainActor in await app.goals.openFromLog() } },
                        closedByUser: { $0.info.showGoalFromLog = false },
                        content: { app, _ in GoalFromLogContent(app: app) })
    }
}

private struct GoalFromLogContent: View {
    let app: AppModel

    var body: some View {
        let goals: GoalsModel = app.goals
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: goals.fromLogHelpText)
                .windowFont(11)
                .foregroundStyle(.secondary)
            pickers(goals, language: language)
            Divider()
            if !goals.error.isEmpty {
                Text(verbatim: goals.error)
                    .windowFont(12)
                    .foregroundStyle(Color(domain: DomainColors.dupe))
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("goalsFromLog.error")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if goals.contests.isEmpty && goals.error.isEmpty {
                        Text(verbatim: language.tr("Žádné závody."))
                            .windowFont(12)
                            .padding(.top, 6)
                    }
                    ForEach(goals.contests, id: \.contestId) { summary in
                        Button {
                            Task { @MainActor in await goals.importFrom(summary) }
                        } label: {
                            HStack(spacing: 10) {
                                Text(verbatim: summary.name ?? "")
                                    .windowFont(12, weight: .bold)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(verbatim: "\(summary.qsoCount) QSO")
                                    .windowFont(12, design: .monospaced)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("goalsFromLog.contest.\(summary.contestId)")
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button(language.tr("Zavřít")) { app.info.showGoalFromLog = false }
                    .windowFont(13)
            }
            .padding(.top, 6)
        }
        .onChange(of: goals.imported) {
            if goals.imported {
                app.info.showGoalFromLog = false
            }
        }
    }

    private func pickers(_ goals: GoalsModel, language: LanguageModel) -> some View {
        let translator: Translator = language.translator
        return HStack(spacing: 10) {
            Text(verbatim: language.tr("Databáze:")).windowFont(12)
            Picker(selection: Binding(get: { goals.selectedDatabase },
                                      set: { name in Task { @MainActor in await goals.selectDatabase(name) } })) {
                ForEach(goals.databases, id: \.self) { name in
                    Text(verbatim: name).tag(name)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("goalsFromLog.database")
            Text(verbatim: language.tr("Pásmo:")).windowFont(12)
            Picker(selection: Binding(get: { goals.band }, set: { goals.band = $0 })) {
                Text(verbatim: GoalEditing.bandLabel(nil, translate: translator)).tag(Band?.none)
                ForEach(Band.allCases, id: \.self) { band in
                    Text(verbatim: band.adif).tag(Band?.some(band))
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("goalsFromLog.band")
        }
        .padding(.vertical, 8)
    }
}
