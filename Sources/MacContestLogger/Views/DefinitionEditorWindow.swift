import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `DefinitionEditorWindow` (`defeditor` 1100×720, `DE:50-237`): the definitions of `contests/` on the left
/// with the new/duplicate/QSO party/county import buttons, the YAML text in the middle, the check and the preview on
/// the right, the save buttons and the footer below. The state is `DefinitionEditorModel`'s; the lists are read again
/// whenever the window appears. Reopened from `config.openWindows` like Kotlin (`showDefinitionEditor`).
struct DefinitionEditorWindowView: View {
    let host: AppHost

    @StateObject private var session = WindowSession(id: "defeditor", persistSize: true,
                                                     defaultSize: CGSize(width: 1100, height: 720))
    @StateObject private var prompts = EditorPromptState()

    private var binder: WindowGeometryBinder { session.binder }

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .navigationTitle(app.language.tr("Editor definic závodů"))
                    .onAppear {
                        binder.setStore(app.geometry)
                        app.definitionEditor.refresh()
                    }
                    .background(WindowAccessor { window in
                        binder.isTerminating = { host.isTerminating }
                        binder.onClose = {
                            // Kotlin's editor state lives in the window: closing it forgets the definition.
                            app.definitionEditor.reset()
                            app.windows.setOpen("defeditor", false)
                        }
                        binder.attach(window)
                    })
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 700, minHeight: 360)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: language)
            HStack(alignment: .top, spacing: 8) {
                DefinitionListColumn(app: app, prompts: prompts)
                    .frame(width: 200)
                DefinitionTextColumn(app: app)
                DefinitionCheckColumn(app: app)
                    .frame(width: 320)
            }
            .frame(maxHeight: .infinity)
            DefinitionEditorFooter(app: app)
        }
        .padding(8)
        .windowFont(13)
        .environment(\.windowFontSize, session.fontSize)
        // The prompt closes only through its buttons and keys.
        .sheet(item: Binding(get: { prompts.prompt }, set: { _ in })) { prompt in
            TextInputSheet(language: language, title: prompt.title, hint: "id", initial: "", uppercase: false,
                           onOk: { prompts.submit(prompt.id, $0) }, onCancel: { prompts.cancel(prompt.id) })
                .id(prompt.id)
        }
    }
}

/// The id prompt of the editor (Kotlin `prompt` + `TextInputDialog(hint = "id", uppercase = false)`).
@MainActor
final class EditorPromptState: ObservableObject {

    struct Prompt: Identifiable {
        let id: Int
        let title: String
        let submit: @MainActor (String) -> Void
    }

    @Published private(set) var prompt: Prompt?
    private var counter = 0

    /// A newer prompt replaces an open one (Kotlin's single `prompt`).
    func ask(_ title: String, submit: @escaping @MainActor (String) -> Void) {
        counter += 1
        prompt = Prompt(id: counter, title: title, submit: submit)
    }

    /// OK: the prompt closes, then its action runs (Kotlin `prompt = null; onOk(it)`).
    func submit(_ id: Int, _ text: String) {
        guard let open = prompt, open.id == id else { return }
        prompt = nil
        open.submit(text)
    }

    func cancel(_ id: Int) {
        guard prompt?.id == id else { return }
        prompt = nil
    }
}

/// „Závody": the ids (the open one highlighted; a click opens it) and the buttons for new definitions.
private struct DefinitionListColumn: View {
    let app: AppModel
    let prompts: EditorPromptState

    var body: some View {
        let editor: DefinitionEditorModel = app.definitionEditor
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: language.tr("Závody"))
                .windowFont(14, weight: .bold)
            WindowFontReader { size in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(editor.ids, id: \.self) { id in
                            row(id, selected: id == editor.currentId, fontSize: size - 1)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            buttons(editor, language)
        }
    }

    private func row(_ id: String, selected: Bool, fontSize: Int) -> some View {
        Button {
            Task {
                await app.definitionEditor.open(id)
            }
        } label: {
            Text(verbatim: id)
                .font(.system(size: CGFloat(fontSize)))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func buttons(_ editor: DefinitionEditorModel, _ language: LanguageModel) -> some View {
        Button(language.tr("Nový ze šablony…")) {
            prompts.ask(language.tr("Id nového závodu (název souboru, např. my-contest)")) { id in
                editor.startNew(id: id)
            }
        }
        Button("Duplikovat…") {
            let title: String = language.tr("Id kopie závodu %s", .string(editor.currentId ?? "null"))
            prompts.ask(title) { id in
                editor.duplicate(id: id)
            }
        }
        .disabled(editor.currentId == nil)
        Button(language.tr("Nová QSO party…")) {
            prompts.ask(language.tr("Id nové QSO party (sada okresů bude <id>_counties)")) { id in
                editor.newQsoParty(id: id)
            }
        }
        Button("Importovat okresy…") {
            ExportPanels.openFile(message: language.tr("Seznam okresů (KÓD,Název na řádek)")) { file in
                prompts.ask(language.tr("Id sady okresů (např. ohqp_counties)")) { id in
                    Task {
                        await editor.importCounties(file: file, setId: id)
                    }
                }
            }
        }
    }
}

/// The text of the open definition, or the hint when none is open.
private struct DefinitionTextColumn: View {
    let app: AppModel

    var body: some View {
        let editor: DefinitionEditorModel = app.definitionEditor
        WindowFontReader { size in
            Group {
                if editor.currentId == nil {
                    Text(verbatim: app.language.tr("Vyber závod vlevo, nebo založ nový ze šablony."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    DefinitionTextView(text: editor.text, fontSize: Double(size - 1),
                                       accessibilityLabel: editor.currentId ?? "") { editor.text = $0 }
                }
            }
            .padding(6)
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// „Kontrola" (the findings), „Náhled" (`DefinitionEditing.summary`), the known sets and the directory.
private struct DefinitionCheckColumn: View {
    let app: AppModel

    var body: some View {
        let editor: DefinitionEditorModel = app.definitionEditor
        let language: LanguageModel = app.language
        WindowFontReader { size in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Kontrola")
                        .windowFont(14, weight: .bold)
                    DefinitionCheckLines(check: editor.check, language: language, fontSize: size - 1)
                    Divider()
                        .padding(.vertical, 4)
                    Text(verbatim: language.tr("Náhled"))
                        .windowFont(14, weight: .bold)
                    if let definition = editor.check?.definition {
                        ForEach(Array(DefinitionEditing.summary(definition).enumerated()), id: \.offset) { item in
                            Text(verbatim: item.element)
                                .font(.system(size: CGFloat(size - 1)))
                        }
                    }
                    Divider()
                        .padding(.vertical, 4)
                    footnotes(editor, language, fontSize: size - 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func footnotes(_ editor: DefinitionEditorModel, _ language: LanguageModel, fontSize: Int) -> some View {
        let sets: String = editor.knownSets.isEmpty ? "—" : editor.knownSets.joined(separator: ", ")
        Text(verbatim: language.tr("Sady násobičů: %s", .string(sets)))
            .font(.system(size: CGFloat(fontSize)))
            .foregroundStyle(.secondary)
        Text(verbatim: language.tr("Jazyk definic: docs/definition-editor.md. Adresář: %s",
                                   .string(editor.contestsDir.path)))
            .font(.system(size: CGFloat(fontSize)))
            .foregroundStyle(.secondary)
    }
}

/// The check's findings: `—` before the first check, „✔ Definice je v pořádku", or `✖`/`⚠` + message per finding.
private struct DefinitionCheckLines: View {
    let check: DefinitionEditing.Check?
    let language: LanguageModel
    let fontSize: Int

    var body: some View {
        if let check {
            if check.issues.isEmpty {
                Text(verbatim: language.tr("✔ Definice je v pořádku"))
                    .foregroundStyle(.mclPrimary)
            } else {
                ForEach(Array(check.issues.enumerated()), id: \.offset) { item in
                    issue(item.element)
                }
            }
        } else {
            Text(verbatim: "—")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func issue(_ issue: ValidationReport.Issue) -> some View {
        let isError: Bool = issue.severity == .error
        let color: NSColor = isError ? DomainColors.dupe : DomainColors.tertiary
        let kind: String = isError ? language.tr("Chyba") : language.tr("Varování")
        return Text(verbatim: (isError ? "✖ " : "⚠ ") + issue.message)
            .accessibilityLabel(Text(verbatim: kind + ": " + issue.message))
            .font(.system(size: CGFloat(fontSize)))
            .foregroundStyle(Color(domain: color))
    }
}

/// „Uložit" (only with changes), „Uložit a přenačíst závody", „Zahodit změny" and the footer (red while the check
/// finds errors).
private struct DefinitionEditorFooter: View {
    let app: AppModel

    var body: some View {
        let editor: DefinitionEditorModel = app.definitionEditor
        let language: LanguageModel = app.language
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(language.tr("Uložit")) {
                Task { await editor.save(reload: false) }
            }
            .disabled(!editor.canSave)
            Button(language.tr("Uložit a přenačíst závody")) {
                Task { await editor.save(reload: true) }
            }
            .disabled(!editor.canSaveAndReload)
            Button(language.tr("Zahodit změny")) {
                editor.discard()
            }
            .disabled(!editor.isDirty)
            Text(verbatim: editor.footerText)
                .foregroundStyle(editor.hasCheckErrors ? Color(domain: DomainColors.dupe) : Color.secondary)
                .lineLimit(2)
        }
    }
}
