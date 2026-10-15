import Foundation

/// N1MM's message when a QSO party log is created: whether the station counts as in-state or out-of-state by the ARRL
/// section in the station data, and a warning when the section does not fit the call.
public enum QsoPartyStatus {

    /// ADIF entities that send an ARRL / RAC section (USA, Canada, Alaska, Hawaii and the US territories).
    public static let sectionEntities: Set<Int> = [291, 1, 6, 110, 202, 285, 43, 182, 9, 20, 103, 123, 138, 166, 174,
                                                   197, 297]

    /// `nil` for a contest without `inState`.
    /// - Parameters:
    ///   - section: my ARRL section (station data)
    ///   - ownEntity: the ADIF entity of my call, `nil` = not known
    public static func message(_ definition: ContestDefinition, section: String, ownEntity: Int?) -> ContestMessage? {
        guard let inState = definition.inState else { return nil }
        let trimmed: String = KotlinText.trim(section).uppercased()
        let sectionStation: Bool = ownEntity.map { sectionEntities.contains($0) } ?? true
        if !sectionStation && !trimmed.isEmpty && trimmed != "DX" {
            return ContestMessage("QSO party: stanice mimo USA a Kanadu má v datech stanice ARRL sekci „DX“, ne „%s“ — oprav ji",
                                  .string(trimmed))
        }
        if trimmed.isEmpty {
            return ContestMessage("QSO party: v datech stanice chybí ARRL sekce — počítám tě jako stanici mimo stát")
        }
        if inState.contains(section: trimmed) {
            return ContestMessage("QSO party: stanice ve státě (sekce %s)", .string(trimmed))
        }
        return ContestMessage("QSO party: stanice mimo stát (sekce %s)", .string(trimmed))
    }
}
