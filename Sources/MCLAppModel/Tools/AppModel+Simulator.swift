import Foundation
import MCLCore

extension AppModel {

    /// The pileup simulator and the Move Multipliers window and the safety gate of: while the simulator
    /// starts or runs, CW goes to it (before the TX gate), voice, digital, tune and the footswitch PTT are refused, and
    /// no QSO is published outward. The pieces that must stay silent ask the simulator, nothing tracks its own flag.
    static func wireSimulator(_ model: AppModel, environment: Environment) {
        let clock: any RescoreClock = environment.keyerClock ?? MainQueueRescoreClock()
        let simulator = SimulatorModel(SimulatorModel.Dependencies(
            hardware: environment.hardware, config: model.config, status: model.status, language: model.language,
            callData: model.callData, clock: clock, random: SystemPileupRandom()))
        simulator.keyer = model.keyer
        model.simulator = simulator
        model.moveMults = MoveMultsModel(MoveMultsModel.Dependencies(
            contest: model.contest, logbook: model.logbook, operating: model.operating, rig: model.rig,
            keyer: model.keyer, status: model.status, language: model.language, now: environment.now))
        model.qtcSending = QtcSending(keyer: model.keyer)

        // Closing the simulator window stops the session, whatever the view does.
        model.windows.onClosed = { [weak simulator] id in
            if id == "simulator" {
                simulator?.windowClosed()
            }
        }
        model.keyer.tx.simulatorRoute = { [weak simulator] message, key in
            simulator?.route(message, key: key) ?? false
        }
        model.keyer.tx.simulatorAbort = { [weak simulator] in
            simulator?.abort()
        }
        model.keyer.tx.rigKeyingGate = { [weak simulator] in
            simulator?.keyingRefusal
        }
        model.rig.keyingGate = { [weak simulator] in
            simulator?.keyingRefusal
        }
        model.logbook.simulatorActive = { [weak simulator] in
            simulator?.isOn ?? false
        }
        model.logbook.onSimulatorQso = { [weak simulator] qso in
            simulator?.qsoLogged(qso)
        }
        model.logbook.outwardGate = { [weak simulator] qso in
            simulator?.allowsPublishing(qso) ?? true
        }
        model.onlineServices.outwardAllowed = { [weak simulator] in
            simulator?.allowsOutwardEffects ?? true
        }
        model.integrations.isSimulated = { [weak simulator] qso in
            simulator?.isSimulated(qso) ?? false
        }
        model.integrations.keyingRefusal = { [weak simulator] in
            simulator?.keyingRefusal
        }
        simulator.liveOutwardService = { [weak model] in
            guard let model else { return nil }
            if model.cluster.isRunning { return model.language.tr("cluster") }
            if model.config.config.scoreReportingEnabled { return model.language.tr("hlášení skóre") }
            if model.integrations.broadcastActive { return model.language.tr("N1MM broadcast") }
            if model.config.config.clubLog.configured() { return model.language.tr("Club Log") }
            return nil
        }
        model.integrations.outwardAllowed = { [weak simulator] in
            simulator?.allowsOutwardEffects ?? true
        }
        // The quit: the session stops and the sound output closes (Kotlin leaves the player open).
        let keyers: @MainActor () async -> Void = model.shutdownServices.keyers
        model.shutdownServices.keyers = { [weak simulator] in
            await keyers()
            await simulator?.shutdown()
        }
    }
}
