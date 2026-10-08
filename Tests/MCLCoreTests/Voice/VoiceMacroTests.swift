import Foundation
import os
import Testing
@testable import MCLCore

/// Control macros in SSB messages: the planner splits a message into audio and actions in message order, the voice
/// keyer performs an action once the audio before it has finished.
@Suite(.ioSafetyNet) struct VoiceMacroTests {

    static let wav = VoiceMessagePlannerTests.wav

    static func plan(_ text: String, functionKeys: [String] = [],
                     speech: VoiceMessagePlanner.Speech? = nil) throws -> VoiceMessagePlanner.Plan {
        var ctx = VoiceMessagePlannerTests.ctx
        ctx.functionKeys = functionKeys
        return try VoiceMessagePlanner.plan(
            text, ctx: ctx, wavDir: wav, lettersDir: VoiceMessagePlannerTests.letters,
            exists: VoiceMessagePlannerTests.existing("cq.wav", "tu.wav", "OK1XOE/59.wav"), speech: speech)
    }

    static func file(_ name: String) -> JavaPath {
        wav.resolve(try! JavaPath(name))
    }

    // MARK: - planner

    @Test func controlMacrosAreActionsNotFiles() throws {
        let p = try Self.plan("cq.wav,{LOG},{WIPE},{RUN},{S&P},{CLEARRIT},{RITCLEAR},{CQFREQ},{NOSPLIT}")
        #expect(p.missing.isEmpty)
        #expect(p.unknownMacros.isEmpty)
        #expect(p.steps == [.play([Self.file("cq.wav")]), .action(.log), .action(.wipe), .action(.run),
                            .action(.searchAndPounce), .action(.clearRit), .action(.clearRit),
                            .action(.cqFrequency), .action(.splitOff)])
    }

    @Test func macrosAreCaseInsensitiveAndTrimmed() throws {
        let p = try Self.plan(" {log} , {s&p}")
        #expect(p.steps == [.action(.log), .action(.searchAndPounce)])
        #expect(p.files.isEmpty)
        #expect(p.missing.isEmpty)
    }

    @Test func actionsKeepTheirPlaceBetweenAudio() throws {
        let p = try Self.plan("{WIPE},cq.wav,{RUN},tu.wav,{LOG}")
        #expect(p.steps == [.action(.wipe), .play([Self.file("cq.wav")]), .action(.run),
                            .play([Self.file("tu.wav")]), .action(.log)])
        #expect(p.files == [Self.file("cq.wav"), Self.file("tu.wav")])
        #expect(p.leadingActions == [.wipe])
        #expect(p.playSteps == [.play([Self.file("cq.wav")]), .action(.run), .play([Self.file("tu.wav")]),
                                .action(.log)])
    }

    @Test func endStopsTheMessage() throws {
        let p = try Self.plan("cq.wav,{END},tu.wav,{LOG},gone.wav,{NOPE}")
        #expect(p.steps == [.play([Self.file("cq.wav")])])
        #expect(p.missing.isEmpty)
        #expect(p.unknownMacros.isEmpty)
        #expect(try Self.plan("{end}").steps.isEmpty)
    }

    @Test func unknownMacrosAreReportedAndNeverPlayed() throws {
        let p = try Self.plan("{CAT1ASC 7},cq.wav,{NOPE},{MYCALL}")
        #expect(p.unknownMacros == ["{CAT1ASC 7}", "{NOPE}"])
        #expect(p.missing.isEmpty)
        #expect(p.files.first == Self.file("cq.wav"))
        // `{MYCALL}` is still the spoken callsign (letters), not an unknown macro.
        #expect(p.files.count > 1)
    }

    @Test func functionKeyChaining() throws {
        let keys = ["cq.wav", "{F3},{LOG}", "tu.wav", "{F2}"]
        let p = try Self.plan("{F1},{F2},{f4}", functionKeys: keys)
        #expect(p.steps == [.play([Self.file("cq.wav"), Self.file("tu.wav")]), .action(.log),
                            .play([Self.file("tu.wav")]), .action(.log)])
        // `{F2}` here is a key of the current set, not a file.
        #expect(p.missing.isEmpty)
    }

    @Test func mixedAudioMacrosAndSpeech() throws {
        let tts = Self.file("tts-1.wav")
        var spoken: [String] = []
        let p = try Self.plan("cq.wav,[hello there],{LOG},OK1XOE/59.wav,{WIPE}", speech: { text in
            spoken.append(text)
            return tts
        })
        #expect(spoken == ["hello there"])
        #expect(p.steps == [.play([Self.file("cq.wav"), tts]), .action(.log),
                            .play([Self.file("OK1XOE/59.wav")]), .action(.wipe)])
    }

    @Test func missingFilesStillReportedBesideMacros() throws {
        let p = try Self.plan("gone.wav,{LOG}")
        #expect(p.missing == ["gone.wav"])
        #expect(p.steps == [.action(.log)])
    }

    @Test func recursionDepthIsBounded() throws {
        let p = try Self.plan("{F1}", functionKeys: ["{F1}"])
        #expect(p.steps.isEmpty)
        #expect(p.unknownMacros == ["{F1}"])
    }

    // MARK: - voice keyer

    private func make(_ events: VoiceKeyerTests.Events, held: Bool = false) -> VoiceKeyer {
        VoiceKeyer(audio: { file, cancelled in
            events.add("play " + (file.description.split(separator: "/").last.map(String.init) ?? ""))
            while held && !cancelled() { Thread.sleep(forTimeInterval: 0.005) }
        }, ptt: { on in events.add(on ? "PTT on" : "PTT off") }, pttDelayMs: { 0 })
    }

    @Test func actionsRunAfterTheAudioBeforeThemWhileKeyed() async {
        let events = VoiceKeyerTests.Events()
        let keyer = make(events)
        let done = VoiceKeyerTests.Done()
        keyer.play(steps: [.play([Self.file("cq.wav")]), .action(.log), .play([Self.file("tu.wav")]), .action(.wipe)],
                   onAction: { events.add("action \($0.rawValue)") }, listener: done.listener)
        #expect(await done.value() == nil)
        keyer.close()
        #expect(events.all == ["PTT on", "play cq.wav", "action LOG", "play tu.wav", "action WIPE", "PTT off"])
    }

    @Test func escapeBeforeTheTrailingActionSkipsIt() async {
        let events = VoiceKeyerTests.Events()
        let keyer = make(events, held: true)
        let done = VoiceKeyerTests.Done()
        keyer.play(steps: [.play([Self.file("cq.wav")]), .action(.log)],
                   onAction: { events.add("action \($0.rawValue)") }, listener: done.listener)
        await events.waitFor { $0.contains("play cq.wav") }
        keyer.stop()
        #expect(await done.value() == nil)
        keyer.close()
        #expect(events.all == ["PTT on", "play cq.wav", "PTT off"])
    }

    @Test func anAudioErrorSkipsTheRestAndReleasesTheKey() async {
        let events = VoiceKeyerTests.Events()
        let keyer = VoiceKeyer(audio: { _, _ in throw VoiceKeyerTests.Failure(description: "boom") },
                               ptt: { on in events.add(on ? "PTT on" : "PTT off") }, pttDelayMs: { 0 })
        let done = VoiceKeyerTests.Done()
        keyer.play(steps: [.play([Self.file("cq.wav")]), .action(.log)],
                   onAction: { events.add("action \($0.rawValue)") }, listener: done.listener)
        #expect(await done.value() == "boom")
        keyer.close()
        #expect(events.all == ["PTT on", "PTT off"])
    }
}
