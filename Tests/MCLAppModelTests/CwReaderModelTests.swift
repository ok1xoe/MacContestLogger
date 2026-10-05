import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The CW Reader window (`CwReaderWindow.kt`): the decoder under a lock fed by the audio queue, the
/// text and speed taken every 150 ms, the calls, the tone field, and the receiver audio held only while the window
/// is open. The audio is synthetic PCM fed into a deviceless capture.
@MainActor @Suite struct CwReaderModelTests {

    /// Open: the listener and the audio user; decoded CW appears after the 150 ms refresh with its speed and calls
    /// (the own call left out); a click on a call fills the call field. Close: the listener and the audio user go,
    /// the input closes, the refresh stops.
    @Test func decodesWhileOpenAndReleasesOnClose() async throws {
        let app = try await KeyingApp.make()
        let reader: CwReaderModel = app.model.makeCwReader()
        #expect(reader.pitchText == "600")
        await reader.open()
        #expect(reader.error == nil)
        #expect(app.model.audio.userNames == ["cwreader"])
        try RadioSignals.feed(app, RadioSignals.cw("CQ DE OK1XOE DL1ABC K", wpm: 25, tone: 600))
        #expect(reader.text.isEmpty)
        app.radioClock.advance(by: 150)
        #expect(reader.text.contains("DL1ABC"), "\(reader.text)")
        #expect(reader.wpm > 0)
        #expect(reader.calls == ["DL1ABC"])
        reader.take("DL1ABC")
        #expect(app.entry.form.call == "DL1ABC")
        reader.close()
        #expect(app.model.audio.userNames.isEmpty)
        await app.settle()
        #expect(!app.model.audio.capture.isRunning)
        #expect(app.radioClock.pendingCount == 0)
        let before: String = reader.text
        app.radioClock.advance(by: 1_000)
        #expect(reader.text == before)
    }

    /// The tone field keeps up to four digits; only 200…3000 Hz retunes the decoder (a 700 Hz signal is decoded
    /// after the field says 700, not after an out-of-range value).
    @Test func toneField() async throws {
        let app = try await KeyingApp.make()
        let reader: CwReaderModel = app.model.makeCwReader()
        await reader.open()
        reader.pitchChanged("7a0x0 9")
        #expect(reader.pitchText == "7009")
        reader.pitchChanged("700")
        #expect(reader.pitchText == "700")
        try RadioSignals.feed(app, RadioSignals.cw("TEST OK2XYZ", wpm: 25, tone: 700))
        app.radioClock.advance(by: 150)
        #expect(reader.text.contains("OK2XYZ"), "\(reader.text)")
        #expect(RadioWindowTexts.readerPlaceholder(reader.pitchText).czech
            == "Čekám na CW na 700 Hz… (zdroj zvuku: Nastavení → Audio → Příjem)")
        reader.clear()
        #expect(reader.text.isEmpty)
        #expect(reader.calls.isEmpty)
        reader.close()
    }

    /// A failed input: the error shows („Zvuk: …" in the window) and no audio user stays registered; closing
    /// releases nothing more.
    @Test func audioErrorIsShown() async throws {
        let app = try await KeyingApp.make()
        app.keying.failAudio("busy")
        let reader: CwReaderModel = app.model.makeCwReader()
        await reader.open()
        #expect(reader.error == "Zvukový vstup není dostupný: busy")
        #expect(app.model.audio.userNames.isEmpty)
        reader.close()
        #expect(app.model.audio.userNames.isEmpty)
    }

    /// The window closes while it still waits for the input another user is starting: its registration, which
    /// lands after the close, is released again — the input is not held for a window that is gone.
    @Test func closeDuringTheStartReleasesTheInput() async throws {
        let app = try await KeyingApp.make()
        let audio: AudioModel = app.model.audio
        app.keying.holdAudioStart()
        let other = Task { await audio.acquire("waterfall") }
        await eventually("start in flight") { app.keying.events.count == 1 }
        let reader: CwReaderModel = app.model.makeCwReader()
        let opening = Task { await reader.open() }
        await runMainQueue()
        reader.close()
        app.keying.releaseAudioStart()
        #expect(await other.value == nil)
        await opening.value
        await app.settle()
        #expect(audio.userNames == ["waterfall"])
        audio.release("waterfall")
        await app.settle()
        #expect(!audio.capture.isRunning)
    }

    /// The window went before its opening task ran: the cancelled `open()` holds nothing (no listener, no input, no
    /// refresh).
    @Test func cancelledOpenHoldsNothing() async throws {
        let app = try await KeyingApp.make()
        let model = app.model.makeCwReader()
        let opening = Task { await model.open() }
        opening.cancel()
        await opening.value
        model.close()
        await app.settle()
        #expect(app.model.audio.userNames.isEmpty)
        #expect(app.keying.events.isEmpty)
        #expect(app.radioClock.pendingCount == 0)
    }

    /// The opening is cancelled while the input is starting (and no close follows): the model gives back the input
    /// and the listener itself.
    @Test func openCancelledDuringTheStartReleases() async throws {
        let app = try await KeyingApp.make()
        let model = app.model.makeCwReader()
        app.keying.holdAudioStart()
        let opening = Task { await model.open() }
        await eventually("start in flight") { app.keying.events.count == 1 }
        opening.cancel()
        app.keying.releaseAudioStart()
        await opening.value
        await app.settle()
        #expect(app.model.audio.userNames.isEmpty)
        #expect(!app.model.audio.capture.isRunning)
        #expect(app.radioClock.pendingCount == 0)
    }

    /// A model that goes away open (its window never closed it) gives the input back as a last resort.
    @Test func modelGoneWithoutCloseReleases() async throws {
        let app = try await KeyingApp.make()
        do {
            let model = app.model.makeCwReader()
            await model.open()
            #expect(app.model.audio.userNames == ["cwreader"])
        }
        await eventually("released") { app.model.audio.userNames.isEmpty }
        await app.settle()
        #expect(!app.model.audio.capture.isRunning)
    }
}
