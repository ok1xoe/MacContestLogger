import Foundation
import os
import Testing
@testable import MCLCore

/// The N1MM per-radio options of `RigConfig` (CI-V address, polling rate, reverse CW, microphone mute, sub receiver,
/// transceiver timeout) and the missing COM port marker. Hardware safety: the daemon command line is only built, never
/// run; the CAT session talks to an in-memory rig through its connector.
@Suite(.ioSafetyNet, .disabled("probe")) struct RigOptionsTests {

    // MARK: - configuration

    /// An old configuration without the new keys loads with the defaults; the keys round-trip.
    @Test func newKeysDefaultAndRoundTrip() throws {
        let old = try JSONDecoder().decode(RigConfig.self, from: Data(#"{"model": 3073, "baud": 19200}"#.utf8))
        #expect(old.model == 3073)
        #expect(old.civAddress == "")
        #expect(old.pollRate == .normal)
        #expect(!old.reverseCw && !old.muteMicOnVoice && !old.subReceiverOn)
        #expect(old.timeoutSeconds == 15)
        var rc = RigConfig()
        rc.civAddress = "94"
        rc.pollRate = .slower100
        rc.reverseCw = true
        rc.muteMicOnVoice = true
        rc.subReceiverOn = true
        rc.timeoutSeconds = 0
        let back = try JSONDecoder().decode(RigConfig.self, from: JSONEncoder().encode(rc))
        #expect(back == rc)
    }

    @Test func civAddressAcceptsN1mmForms() {
        #expect(RigConfig.civAddressHamlib("94") == "0x94")
        #expect(RigConfig.civAddressHamlib("94H") == "0x94")
        #expect(RigConfig.civAddressHamlib(" 0xA4 ") == "0xa4")
        #expect(RigConfig.civAddressHamlib("e") == "0x0e")
        #expect(RigConfig.civAddressHamlib("") == nil)
        #expect(RigConfig.civAddressHamlib("1FF") == nil)
        #expect(RigConfig.civAddressHamlib("ZZ") == nil)
    }

    @Test func pollRateSlowsTheInterval() {
        #expect(PollRate.normal.interval(base: 500) == 500)
        #expect(PollRate.slower50.interval(base: 500) == 750)
        #expect(PollRate.slower100.interval(base: 500) == 1000)
    }

    // MARK: - rigctld command line

    /// The CI-V address goes to the daemon as `--set-conf civaddr=0xNN`, only with a serial device and a valid value.
    @Test func civAddressInDaemonCommand() {
        let serial = SerialParams(dataBits: 8, stopBits: 1, parity: "None", handshake: "", rts: "Unset", dtr: "Unset")
        let icom = RigctldProcessManager.command(binary: "rigctld", model: 3073, device: "cu.usb", baud: 19200,
                                                 port: 4600, serial: serial, civAddress: "94H")
        #expect(icom == ["rigctld", "-vvv", "-m", "3073", "-r", "/dev/cu.usb", "-s", "19200", "--set-conf",
                         "data_bits=8,stop_bits=1,serial_parity=None", "--set-conf", "civaddr=0x94", "-t", "4600"])
        let none = RigctldProcessManager.command(binary: "rigctld", model: 3073, device: "cu.usb", baud: 19200,
                                                 port: 4600, serial: nil, civAddress: "")
        #expect(none == ["rigctld", "-vvv", "-m", "3073", "-r", "/dev/cu.usb", "-s", "19200", "-t", "4600"])
        let invalid = RigctldProcessManager.command(binary: "rigctld", model: 3073, device: "cu.usb", baud: 0,
                                                    port: 4600, serial: nil, civAddress: "XYZ")
        #expect(!invalid.contains { $0.hasPrefix("civaddr") })
        let noDevice = RigctldProcessManager.command(binary: "rigctld", model: 1, device: "", baud: 0, port: 4600,
                                                     serial: nil, civAddress: "94")
        #expect(noDevice == ["rigctld", "-vvv", "-m", "1", "-t", "4600"])
    }

    // MARK: - microphone mute

    @Test func micGainParsedFromExtendedReply() {
        #expect(MicMute.gain(in: ["get_level: MICGAIN", "0.500000"]) == "0.500000")
        #expect(MicMute.gain(in: ["get_level: MICGAIN", "Level Value: 0.25"]) == "0.25")
        #expect(MicMute.gain(in: ["get_level: MICGAIN"]) == nil)
        #expect(MicMute.gain(in: []) == nil)
    }

    @Test func muteSavesAndRestoresTheGain() {
        let rig = RawRig()
        rig.replies["l MICGAIN"] = RigRawReply(lines: ["get_level: MICGAIN", "0.400000"], code: 0)
        let saved = MicMute.mute(rig)
        #expect(saved == "0.400000")
        MicMute.restore(rig, gain: "0.400000")
        #expect(rig.raw == ["l MICGAIN", "L MICGAIN 0", "L MICGAIN 0.400000"])
    }

    /// A rig without `MICGAIN` (an error code) is left alone.
    @Test func unsupportedRigIsNotMuted() {
        let rig = RawRig()
        rig.replies["l MICGAIN"] = RigRawReply(lines: [], code: -11)
        #expect(MicMute.mute(rig) == nil)
        #expect(rig.raw == ["l MICGAIN"])
    }

    // MARK: - radio problem alert

    @Test func radioProblemDueAfterTimeout() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        #expect(RadioProblemAlert.delay(timeoutSeconds: 15, lastContact: t0, now: t0.addingTimeInterval(5)) == 10)
        #expect(RadioProblemAlert.delay(timeoutSeconds: 15, lastContact: t0, now: t0.addingTimeInterval(20)) == 0)
        #expect(RadioProblemAlert.delay(timeoutSeconds: 0, lastContact: t0, now: t0) == nil)
        #expect(!RadioProblemAlert.isDue(lost: true, connected: false, timeoutSeconds: 15, lastContact: t0,
                                         now: t0.addingTimeInterval(14)))
        #expect(RadioProblemAlert.isDue(lost: true, connected: false, timeoutSeconds: 15, lastContact: t0,
                                        now: t0.addingTimeInterval(15)))
        #expect(!RadioProblemAlert.isDue(lost: false, connected: false, timeoutSeconds: 15, lastContact: t0,
                                         now: t0.addingTimeInterval(60)))
        #expect(!RadioProblemAlert.isDue(lost: true, connected: true, timeoutSeconds: 15, lastContact: t0,
                                         now: t0.addingTimeInterval(60)))
        #expect(!RadioProblemAlert.isDue(lost: true, connected: false, timeoutSeconds: 0, lastContact: t0,
                                         now: t0.addingTimeInterval(60)))
    }

    // MARK: - missing port

    @Test func missingPortIsMarked() {
        let available = ["/dev/cu.usbserial-A", "/dev/tty.usbserial-A"]
        #expect(!SerialPortChoice.isMissing("", available: available))
        #expect(!SerialPortChoice.isMissing("/dev/cu.usbserial-A", available: available))
        #expect(SerialPortChoice.isMissing("/dev/cu.usbserial-B", available: available))
        #expect(SerialPortChoice.label("/dev/cu.usbserial-B", available: available) == "* /dev/cu.usbserial-B")
        #expect(SerialPortChoice.label("/dev/cu.usbserial-A", available: available) == "/dev/cu.usbserial-A")
    }

    // MARK: - CAT session

    /// Reverse CW: CW goes as `M CWR 0`, other modes as usual; the sub receiver option switches dual watch on once at
    /// connect.
    @Test func sessionAppliesReverseCwAndDualWatch() async throws {
        let rig = RawRig()
        let rec = CatSessionTests.Recorder()
        let session = CatSessionTests.makeSession(rec, log: CatTrafficLog(maxLines: 100), connector: { _, _ in rig })
        var rc = CatSessionTests.rigConfig(.connectRunning, port: FreeLoopbackPort.take())
        rc.reverseCw = true
        rc.subReceiverOn = true
        session.connect(rc)
        try await rec.wait { $0.last?.connected == true }
        try await onOwnThread {
            try session.setMode(.cw, freqHz: 7_010_000)
            try session.setMode(.ssb, freqHz: 7_100_000)
        }
        #expect(rig.raw == ["U DUAL_WATCH 1", "M CWR 0"])
        #expect(rig.modes == ["SSB"])
        session.disconnect(nil)
    }

    /// Without the options nothing extra goes to the rig.
    @Test func sessionWithoutOptionsSendsPlainCw() async throws {
        let rig = RawRig()
        let rec = CatSessionTests.Recorder()
        let session = CatSessionTests.makeSession(rec, log: CatTrafficLog(maxLines: 100), connector: { _, _ in rig })
        session.connect(CatSessionTests.rigConfig(.connectRunning, port: FreeLoopbackPort.take()))
        try await rec.wait { $0.last?.connected == true }
        try await onOwnThread {
            try session.setMode(.cw, freqHz: 7_010_000)
        }
        #expect(rig.raw.isEmpty)
        #expect(rig.modes == ["CW"])
        session.disconnect(nil)
    }

    /// A user disconnect is not a lost connection (no radio problem alert).
    @Test func userDisconnectIsNotLost() async throws {
        let rig = RawRig()
        let rec = CatSessionTests.Recorder()
        let session = CatSessionTests.makeSession(rec, log: CatTrafficLog(maxLines: 100), connector: { _, _ in rig })
        session.connect(CatSessionTests.rigConfig(.connectRunning, port: FreeLoopbackPort.take()))
        try await rec.wait { $0.last?.connected == true }
        session.disconnect(nil)
        #expect(rec.last?.lost == false)
    }
}

/// An in-memory rig recording raw commands and modes.
final class RawRig: RigController, @unchecked Sendable {
    private let lock = NSLock()
    private var rawLog: [String] = []
    private var modeLog: [String] = []
    var replies: [String: RigRawReply] = [:]

    var raw: [String] { lock.withLock { rawLog } }
    var modes: [String] { lock.withLock { modeLog } }

    func read() throws -> RigState { RigState(freqHz: 7_010_000, mode: .cw, rawMode: "CW", passband: 500) }
    func setFrequencyHz(_ freqHz: Int64) throws {}
    func setMode(_ mode: Mode?, freqHz: Int64) throws { lock.withLock { modeLog.append(mode?.rawValue ?? "nil") } }
    func setPtt(_ on: Bool) throws {}
    func sendMorse(_ text: String) throws {}
    func stopMorse() throws {}
    func setCwSpeed(_ wpm: Int) throws {}
    func isConnected() -> Bool { true }
    func close() {}

    func sendRaw(_ command: String) throws -> RigRawReply {
        lock.withLock {
            rawLog.append(command)
            return replies[command] ?? RigRawReply(lines: [], code: 0)
        }
    }
}
