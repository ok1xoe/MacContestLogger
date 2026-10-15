import Foundation
import MCLCore

/// N1MM „Edit Section List" / „Import Section List": the county / section lists of the chosen contest.
extension NewContestModel {

    /// The list being edited in the sheet.
    public struct SectionEditor: Equatable, Sendable {
        public let setId: String
        public var text: String
    }

    /// The editable lists (CSV-backed multiplier sets) of the chosen contest.
    public var sectionSets: [String] {
        guard let dir = multipliersDir else { return [] }
        return SectionListFile.editableSets(definition, multipliersDir: dir)
    }

    /// Has the list been edited (the shipped one can be put back)?
    public func sectionsEdited(_ setId: String) -> Bool {
        guard let dir = multipliersDir else { return false }
        _ = sectionRevision
        return SectionListFile.hasBackup(setId, multipliersDir: dir)
    }

    /// „Upravit seznam…": the list in the editor sheet.
    public func editSections(_ setId: String) {
        guard let dir = multipliersDir else { return }
        do {
            sectionEditor = SectionEditor(setId: setId, text: try SectionListFile.read(setId, multipliersDir: dir))
            sectionMessage = nil
        } catch {
            sectionMessage = ContestMessage("Seznam %s nelze načíst", .string(setId))
        }
    }

    /// The sheet's „Uložit": the list written, the contest data reloaded.
    public func saveSections() async {
        guard let editor = sectionEditor, let dir = multipliersDir else { return }
        do {
            let count: Int = try SectionListFile.save(editor.setId, text: editor.text, multipliersDir: dir)
            sectionEditor = nil
            sectionRevision += 1
            sectionMessage = ContestMessage("Seznam %s uložen: %s položek", .string(editor.setId), .int(count))
            await sectionsChanged?()
        } catch {
            sectionMessage = ContestMessage("Seznam %s nelze uložit (prázdný nebo chyba zápisu)", .string(editor.setId))
        }
    }

    /// „Obnovit původní seznam": the shipped list back, the contest data reloaded.
    public func restoreSections(_ setId: String) async {
        guard let dir = multipliersDir else { return }
        do {
            guard try SectionListFile.restore(setId, multipliersDir: dir) else { return }
            sectionRevision += 1
            sectionMessage = ContestMessage("Seznam %s obnoven", .string(setId))
            await sectionsChanged?()
        } catch {
            sectionMessage = ContestMessage("Seznam %s nelze obnovit", .string(setId))
        }
    }
}
