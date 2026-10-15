import Foundation
import MCLCore
import Observation

/// The built-in RTTY modem's receive side: each Digital Interface window feeds its receiver from a receiver audio
/// input while it is open (N1MM runs MMTTY inside the Digital Interface). The usual SO2R / SO2V setup is one stereo
/// sound card input — left = receiver 1, right = receiver 2 (N1MM: "2 RX: audio left, audio right"); each receiver can
/// also take radio 2's own input and the left, right or mixed channel (`BuiltinModemSetup`). The inputs are shared
/// with the waterfall, the CW reader and the recorder (`AudioModel`).
///
/// One decoder per receiver for now (`decodersPerReceiver`); N1MM can run a second decoder on the same receiver.
@Observable @MainActor
public final class BuiltinModemModel {

    /// Decoders on one receiver's audio (N1MM's second decoder window is not built yet).
    public static let decodersPerReceiver = 1
    /// The audio users (`AudioModel.acquire`).
    static let users: [String] = ["rtty", "rtty2"]

    struct Attachment {
        let audio: AudioModel
        let listener: AudioCapture.ListenerID
    }

    @ObservationIgnored let hub: BuiltinModemHub
    /// The multi-channel receivers, one per receiver (fed with the receiver's audio).
    @ObservationIgnored public let banks: [BuiltinChannelBank]
    @ObservationIgnored private let audio: AudioModel
    @ObservationIgnored private let audio2: AudioModel
    @ObservationIgnored private let setup: @MainActor () -> BuiltinModemSetup
    @ObservationIgnored private var attached: [Attachment?] = [nil, nil]
    /// Why a receiver has no audio (the input could not be opened), `nil` = it listens or is not attached.
    public private(set) var audioErrors: [String?] = [nil, nil]

    init(hub: BuiltinModemHub, audio: AudioModel, audio2: AudioModel, dataDir: URL,
         setup: @escaping @MainActor () -> BuiltinModemSetup) {
        profileStore = BuiltinModemProfiles(directory: dataDir)
        banks = hub.channels.map { BuiltinChannelBank(source: $0) }
        self.hub = hub
        self.audio = audio
        self.audio2 = audio2
        self.setup = setup
        lastSetup = setup()
        observeSetup()
    }

    @ObservationIgnored private var lastSetup: BuiltinModemSetup
    @ObservationIgnored let profileStore: BuiltinModemProfiles
    /// The profile slots (MMTTY's profiles, 16; `nil` = empty), read on first use and after every change.
    public private(set) var profiles: [BuiltinModemProfile?] = []
    @ObservationIgnored private var profilesRead = false

    /// The slots for the menus.
    public var profileSlots: [BuiltinModemProfile?] {
        if !profilesRead {
            profilesRead = true
            profiles = profileStore.load()
        }
        return profiles
    }

    /// A profile onto a receiver (with linked tuning onto both); `false` = the slot is empty.
    @discardableResult
    public func applyProfile(_ slot: Int, side: Int) -> Bool {
        let slots: [BuiltinModemProfile?] = profileSlots
        guard slots.indices.contains(slot), let profile = slots[slot] else { return false }
        let side: Int = Self.clamp(side)
        hub.channels[side].apply(profile: profile.values)
        if hub.currentSettings.linked {
            hub.channels[1 - side].apply(profile: profile.values)
        }
        return true
    }

    /// The receiver's current setup saved as a profile; the error text, `nil` = saved.
    public func saveProfile(_ slot: Int, name: String, side: Int) -> String? {
        let trimmed: String = name.trimmingCharacters(in: .whitespaces)
        let profile = BuiltinModemProfile(name: trimmed.isEmpty ? "Profil " + String(slot + 1) : trimmed,
                                          values: hub.channels[Self.clamp(side)].profileValues())
        return store(profile, slot: slot)
    }

    /// Clears a slot; the error text, `nil` = done.
    public func deleteProfile(_ slot: Int) -> String? {
        store(nil, slot: slot)
    }

    private func store(_ profile: BuiltinModemProfile?, slot: Int) -> String? {
        do {
            try profileStore.save(profile, slot: slot)
        } catch {
            switch error {
            case .unreadable: return BuiltinModemProfiles.fileName + ": unreadable, not overwritten"
            case .badSlot(let bad): return "slot " + String(bad)
            case .io(let text): return text
            }
        }
        profiles = profileStore.load()
        profilesRead = true
        return nil
    }

    /// A change of the options (Settings): the transmit options go to the hub, an attached receiver whose input or
    /// channel changed listens again.
    private func observeSetup() {
        withObservationTracking {
            _ = setup()
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                let now: BuiltinModemSetup = self.setup()
                let before: BuiltinModemSetup = self.lastSetup
                self.lastSetup = now
                self.hub.configure(BuiltinModemHub.Settings(
                    level: now.outputLevel, devices: [now.outputDevice(side: 0), now.outputDevice(side: 1)],
                    linked: now.flag(.linkedTuning)))
                for bank in self.banks where bank.configuration.enabled {
                    var config: BuiltinChannelBank.Config = bank.configuration
                    config.maxChannels = now.channelCount
                    config.timeout = now.channelTimeout
                    bank.configure(config)
                }
                for side in 0...1 where now.input(side: side) != before.input(side: side)
                    || now.channel(side: side) != before.channel(side: side) {
                    Task { await self.reattach(side) }
                }
                self.observeSetup()
            }
        }
    }

    private static func clamp(_ side: Int) -> Int {
        min(max(side, 0), 1)
    }

    /// The receiver of a side.
    public func channel(_ side: Int) -> BuiltinRttyChannel {
        hub.channels[Self.clamp(side)]
    }

    /// The receiver listens (its window is open and the input runs or is starting).
    public func isAttached(_ side: Int) -> Bool {
        attached[Self.clamp(side)] != nil
    }

    /// The receiver starts listening to its input; a failure is kept in `audioErrors`.
    public func attach(_ side: Int) async {
        let side: Int = Self.clamp(side)
        guard attached[side] == nil else { return }
        let options: BuiltinModemSetup = setup()
        let source: AudioModel = options.input(side: side) == .radio2 ? audio2 : audio
        let pick: BuiltinModemSetup.Channel = options.channel(side: side)
        let channel: BuiltinRttyChannel = hub.channels[side]
        let bank: BuiltinChannelBank = banks[side]
        let listener: AudioCapture.ListenerID = source.addStereoListener { left, right in
            let samples: [Double] = pick.pick(left, right)
            channel.receive(samples)
            bank.feed(samples)
        }
        let attachment = Attachment(audio: source, listener: listener)
        attached[side] = attachment
        audioErrors[side] = nil
        let failure: String? = await source.acquire(Self.users[side])
        guard let failure else { return }
        audioErrors[side] = failure
        if let current = attached[side], current.listener == listener {
            source.removeStereoListener(listener)
            attached[side] = nil
        }
    }

    /// The receiver stops listening; the last user of the input closes it.
    public func detach(_ side: Int) {
        let side: Int = Self.clamp(side)
        guard let attachment = attached[side] else { return }
        attached[side] = nil
        attachment.audio.removeStereoListener(attachment.listener)
        attachment.audio.release(Self.users[side])
    }

    /// The audio options changed (input or channel): an attached receiver listens again with the new ones.
    public func reattach(_ side: Int) async {
        guard isAttached(side) else { return }
        detach(side)
        await attach(side)
    }

    /// The multi-channel receiver of a side on or off, with the configured limits.
    public func setChannels(_ side: Int, on: Bool) {
        let options: BuiltinModemSetup = setup()
        var config = BuiltinChannelBank.Config()
        config.enabled = on
        config.maxChannels = options.channelCount
        config.timeout = options.channelTimeout
        banks[Self.clamp(side)].configure(config)
    }

    /// A tuning change made in the window (mark, shift, speed, the switches); with linked tuning both receivers.
    public func tune(_ side: Int, _ change: (inout BuiltinRttyChannel.Tuning) -> Void) {
        hub.tune(side, change)
    }
}
