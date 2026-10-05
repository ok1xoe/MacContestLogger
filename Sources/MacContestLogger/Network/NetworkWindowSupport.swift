import MCLAppModel
import SwiftUI

/// A selectable chip (Kotlin `FilterChip`): the recipient of the chat, the runner of the partner window, the filters
/// of the WSJT-X decodes.
struct NetworkChip: View {
    let label: String
    let selected: Bool
    var identifier: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: label)
                .windowFont(12)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.28) : Color.clear))
                .overlay(Capsule().stroke(selected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
