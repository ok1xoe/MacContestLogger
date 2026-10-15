import Foundation
import MCLCore

/// The spectrum display over the network (N1MM+): „Receive spectrum data" — N1MM spectrum datagrams from SDR
/// programs on UDP 13064, shown as the external source — and „Relay Options → Broadcast on IP port(s)" — the shown
/// spectrum sent to other stations under a source name. Both are off by default, bound / sent only while the window
/// is open, never with the inert network ports (`MCL_INERT_NETWORK`); the socket work runs on its own lane.
extension WaterfallModel {

    /// The source the display shows (N1MM „Spectrum Source").
    var activeSource: any SpectrumSource {
        setup.source == .external ? externalSource : audioSource
    }

    /// The bound receive port (`nil` = not listening).
    public var receivePort: Int? {
        listener.map(\.boundPort)
    }

    /// Opens, moves or closes the UDP receiver to match the options (window open, receive on, a readable bind).
    func applyNetwork() {
        let setup: SpectrumSetup = self.setup
        guard isOpen, setup.flag(.udpReceive), let network, !network.isInert,
              let bind = setup.udpBindAddress else {
            stopReceiving()
            return
        }
        let key: String = bind.host + ":" + String(bind.port)
        guard key != listenerBind else { return }
        stopReceiving()
        listenerBind = key
        bindGeneration += 1
        let generation: Int = bindGeneration
        let make = network.udp.makeSpectrumListener
        let source: ExternalSpectrumSource = externalSource
        socketQueue.async { [weak self] in
            let made: Result<(any UdpListening)?, any Error> = Result {
                try make(bind.host, bind.port) { packet in
                    source.accept(packet)
                }
            }
            MainHop.post { [weak self] in
                guard let self, self.bindGeneration == generation, self.isOpen else {
                    if case .success(let listener) = made {
                        listener?.close()
                    }
                    return
                }
                switch made {
                case .success(let listener):
                    self.listener = listener
                    self.receiveError = nil
                    listener?.start()
                case .failure(let error):
                    self.receiveError = ErrorText.message(error)
                }
            }
        }
    }

    /// Closes the UDP receiver (the option went off, the window closed).
    func stopReceiving() {
        bindGeneration += 1
        listenerBind = nil
        receiveError = nil
        listener?.close()
        listener = nil
    }

    /// Waits for the socket lane (tests).
    func settleSockets() async {
        let queue: DispatchQueue = socketQueue
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                continuation.resume()
            }
        }
    }

    /// N1MM's relay: five lines a second of the shown spectrum to the targets under the relay name. An external
    /// source of the same name is not sent back out (no loop).
    func relayIfDue() {
        let setup: SpectrumSetup = self.setup
        guard isOpen, setup.flag(.relayEnabled), let network, !network.isInert else { return }
        relayCountdown -= 1
        guard relayCountdown <= 0 else { return }
        relayCountdown = 2
        let name: String = KotlinStrings.trim(setup.text(.relayName))
        if setup.source == .external, externalSource.currentName == name {
            return
        }
        let targets: [Target] = Target.parseAll(setup.text(.relayTargets))
        guard !targets.isEmpty, let frame = pipeline.currentFrame() else { return }
        let send = network.udp.sendDatagram
        socketQueue.async {
            let bytes: [UInt8] = SpectrumXml.serialize(SpectrumPacket.relay(frame, name: name.isEmpty ? "MCL" : name))
            for target in targets {
                try? send(bytes, target.host, Int(target.port))
            }
        }
    }

    /// The source names heard so far, for the picker.
    func noteHeardSources() {
        let names: [String] = externalSource.heardNames
        if names != heardSources {
            heardSources = names
        }
    }
}
