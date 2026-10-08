import AppKit
import MCLAppModel
import MCLCore
import SwiftUI
import UniformTypeIdentifiers

/// The line under an SSB F-key row: the message's file (name and length) and Record, Play, Choose WAV and Delete.
/// A message that is not a single wav file shows why it has no file instead.
struct VoiceMessageControls: View {
    let studio: VoiceMessageStudio
    let language: LanguageModel
    let request: VoiceMessageStudio.Request

    var body: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 32)
            switch studio.target(for: request) {
            case .unavailable(let reason):
                SettingsCaption(language.text(VoiceMessageStudio.explanation(reason)))
            case .target(let path):
                controls(path)
            }
            Spacer(minLength: 0)
        }
    }

    private func controls(_ path: JavaPath) -> some View {
        let slot: VoiceMessageStudio.Slot = request.slot
        let recordingHere: Bool = studio.recordingSlot == slot
        let playingHere: Bool = studio.playingSlot == slot
        let file: VoiceMessageFile? = studio.files[slot]
        let otherRecording: Bool = studio.isRecording && !recordingHere
        return HStack(spacing: 8) {
            if recordingHere {
                SettingsButton(recordingTitle) { studio.stopRecording() }
                    .disabled(studio.recordingStarting)
            } else {
                SettingsButton(language.tr("Nahrát")) { studio.record(request) }
                    .disabled(studio.isRecording)
            }
            SettingsButton(playingHere ? language.tr("Stop") : language.tr("Přehrát")) { studio.play(request) }
                .disabled(file == nil || studio.isRecording)
            SettingsButton(language.tr("Vybrat WAV…")) { choose() }
                .disabled(studio.isRecording)
            SettingsButton(language.tr("Smazat")) { studio.delete(request) }
                .disabled(file == nil || studio.isRecording)
            SettingsCaption(summary(path, file, busy: otherRecording))
        }
    }

    private var recordingTitle: String {
        language.tr("● Stop · %s s", .int(studio.elapsedSeconds))
    }

    private func summary(_ path: JavaPath, _ file: VoiceMessageFile?, busy: Bool) -> String {
        let name: String = path.description.split(separator: "/").last.map(String.init) ?? path.description
        guard let file else { return language.tr("%s — soubor chybí", .string(name)) }
        guard let seconds = file.seconds else { return language.tr("%s — nečitelný wav", .string(name)) }
        return language.tr("%s · %.1f s", .string(name), .double(seconds))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = language.tr("Vyber zvukový soubor pro F%s", .int(request.slot.index + 1))
        panel.allowedContentTypes = VoiceWavImport.extensions.compactMap { UTType(filenameExtension: $0) }
        let request: VoiceMessageStudio.Request = self.request
        let studio: VoiceMessageStudio = self.studio
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { studio.pick(request, from: url) }
        }
    }
}

/// The wav folder and the result line under the SSB keys, and the question before a file is replaced or deleted.
struct VoiceMessageFooter: View {
    let studio: VoiceMessageStudio
    let language: LanguageModel
    let wavDir: String

    var body: some View {
        HStack(spacing: 8) {
            SettingsButton(language.tr("Otevřít složku ve Finderu")) {
                if let url = studio.folder(wavDir: wavDir) {
                    NSWorkspace.shared.open(url)
                }
            }
            SettingsCaption(studio.wavDirectory(wavDir))
            Spacer(minLength: 0)
        }
        if let notice = studio.notice {
            SettingsCaption(language.text(notice))
        }
        Color.clear.frame(height: 0)
            .alert(promptTitle, isPresented: Binding(get: { studio.prompt != nil },
                                                      set: { if !$0 { studio.cancelPrompt() } })) {
                if let prompt = studio.prompt {
                    Button(language.text(prompt.confirm), role: prompt.destructive ? .destructive : nil) {
                        studio.confirmPrompt()
                    }
                    Button(language.tr("Zrušit"), role: .cancel) { studio.cancelPrompt() }
                }
            }
    }

    private var promptTitle: String {
        studio.prompt.map { language.text($0.message) } ?? ""
    }
}
