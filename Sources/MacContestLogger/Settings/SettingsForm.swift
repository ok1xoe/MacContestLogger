import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The form pieces of the Settings window (Kotlin `ui/components/FormKit.kt`: `Grp`, `Field`, `LabeledRow`, `Cap`,
/// `LabeledCheckbox`, `LabeledRadio`, `KitTextField`, `KitDropdown`). Every text derives its size from the window's
/// font stepper.

/// `Grp`: a bordered group with a bold title in the accent colour.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title)
                .windowFont(13, weight: .bold)
                .foregroundStyle(.tint)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        )
    }
}

/// `Field`: a small caption above its control.
struct SettingsField<Content: View>: View {
    let caption: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: caption)
                .windowFont(11)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// `LabeledRow`: the label on the left (fixed width, right-aligned), the controls on the right.
struct SettingsLabeledRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 96
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(verbatim: label)
                .windowFont(11)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(width: labelWidth, alignment: .trailing)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `Cap`: a small secondary text that wraps.
struct SettingsCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .windowFont(11)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A body text of the form (Kotlin `bodyMedium`/`labelMedium`), optionally in the error colour.
struct SettingsText: View {
    let text: String
    var size: Double = 13
    var weight: Font.Weight = .regular
    var isError: Bool = false

    init(_ text: String, size: Double = 13, weight: Font.Weight = .regular, isError: Bool = false) {
        self.text = text
        self.size = size
        self.weight = weight
        self.isError = isError
    }

    var body: some View {
        Text(verbatim: text)
            .windowFont(size, weight: weight)
            .foregroundStyle(isError ? Color(domain: DomainColors.dupe) : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `LabeledCheckbox`.
struct SettingsCheckbox: View {
    let label: String
    @Binding var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(verbatim: label)
                .windowFont(13)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.checkbox)
        .disabled(!enabled)
    }
}

/// `LabeledRadio`: a radio button with its label; `action` selects it.
struct SettingsRadio: View {
    let label: String
    let selected: Bool
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                Text(verbatim: label)
                    .windowFont(13)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// `FilterChip`: a small toggle button that shows whether it is selected.
struct SettingsChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: label)
                .windowFont(12, weight: selected ? .semibold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// `KitDropdown`: the current value on a button, the choices in its menu (a blank choice reads „— žádný —").
struct SettingsDropdown: View {
    let label: String
    let options: [String]
    let language: LanguageModel
    var enabled: Bool = true
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    onSelect(option)
                } label: {
                    Text(verbatim: KotlinStrings.isBlank(option) ? language.tr("— žádný —") : option)
                }
            }
        } label: {
            Text(verbatim: label)
                .windowFont(13)
                .lineLimit(1)
        }
        .menuStyle(.button)
        .disabled(!enabled)
        .accessibilityValue(Text(verbatim: label))
    }
}

/// `KitTextField`: a single-line monospaced field (an `NSTextField`, a secure one for passwords). The field's text
/// goes through `filter` as it is typed (Kotlin's `onValueChange` filters), keeping the caret; a pending composition
/// (dead key, input method) is filtered only once it is committed, as in the entry window's fields.
struct SettingsTextField: NSViewRepresentable {
    @Binding var text: String
    var filter: SettingsInputFilter = .none
    var isPassword: Bool = false
    var isError: Bool = false
    var accessibilityLabel: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isPassword ? NSSecureTextField(frame: .zero) : NSTextField(frame: .zero)
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.wantsLayer = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        let size: Double = WindowFont.size(13, windowSize: context.environment.windowFontSize)
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
        if field.font != font {
            field.font = font
        }
        field.isEnabled = context.environment.isEnabled
        field.setAccessibilityLabel(accessibilityLabel)
        field.layer?.borderWidth = isError ? 1 : 0
        field.layer?.borderColor = DomainColors.dupe.cgColor
        let editor: NSTextView? = field.currentEditor() as? NSTextView
        // Not while the input system composes (marked text is not in the binding yet).
        if editor?.hasMarkedText() == true {
            return
        }
        let current: String = editor?.string ?? field.stringValue
        if current != text {
            field.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsTextField?

        func controlTextDidChange(_ notification: Notification) {
            guard let parent, let field = notification.object as? NSTextField else { return }
            guard let editor = field.currentEditor() as? NSTextView else {
                parent.text = parent.filter.apply(field.stringValue)
                return
            }
            if editor.hasMarkedText() {
                return
            }
            let typed: String = editor.string
            let filtered: String = parent.filter.apply(typed)
            if filtered != typed {
                let caret: Int = editor.selectedRange().location
                let before: String = Self.prefix(typed, utf16Count: caret)
                let newCaret: Int = parent.filter.apply(before).utf16.count
                editor.string = filtered
                editor.setSelectedRange(NSRange(location: min(newCaret, filtered.utf16.count), length: 0))
            }
            parent.text = filtered
        }

        /// The first `utf16Count` UTF-16 units of `text`, rounded down to a whole character.
        private static func prefix(_ text: String, utf16Count: Int) -> String {
            let units: String.UTF16View = text.utf16
            let end: String.Index = units.index(units.startIndex, offsetBy: min(utf16Count, units.count))
            let rounded: String.Index = end.samePosition(in: text) ?? text.startIndex
            return String(text[..<rounded])
        }
    }
}

/// A delete button with a trash icon (Kotlin `IconButton(Icons.Filled.Delete)`), its description as the tooltip.
struct SettingsDeleteButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        IconButton(symbol: "trash", label: help, action: action)
            .buttonStyle(.borderless)
    }
}

/// `ifBlank { fallback }` of Kotlin.
func ifBlank(_ text: String, _ fallback: String) -> String {
    KotlinStrings.isBlank(text) ? fallback : text
}

/// A button with a verbatim title (Kotlin `OutlinedButton`/`Button`; `borderless` = `TextButton`).
struct SettingsButton: View {
    let title: String
    var borderless: Bool = false
    let action: () -> Void

    init(_ title: String, borderless: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.borderless = borderless
        self.action = action
    }

    var body: some View {
        if borderless {
            button.buttonStyle(.borderless)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            Text(verbatim: title)
        }
    }
}

/// A view's own value that outlives view updates (Kotlin `remember { mutableStateOf(…) }`), held with
/// `@StateObject`.
@MainActor
final class ViewState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
