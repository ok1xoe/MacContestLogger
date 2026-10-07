import Foundation

/// Which call-field text commands a plugin may run with the `app.command` permission. An allow-list written as an
/// exhaustive switch (no `default`): a new command does not compile until it is decided here. Allowed are only
/// tuning and mode commands, switching ESM, CQ repeat or dupe working **off**, the version, the rescore, the CAT
/// window and refreshing the log. Everything that can transmit, reach a network, run scripts, change the
/// configuration, the operator, the contest or the logbook, or open dialogs is refused.
public enum PluginCommandPolicy {

    /// Why a command is refused (`nil` = allowed).
    public static func refusal(_ command: CallFieldCommand) -> String? {
        let notFromPlugins = "not allowed from plugins"
        switch command {
        case .qsy, .otherVfo, .split, .splitOff, .rit, .swapVfo, .changeMode, .version, .esmOff, .rescore:
            return nil
        case .toggle(let setting, let on):
            switch setting {
            case .cqRepeat:
                return on ? "CQ repeat transmits" : nil
            case .workDupes:
                return nil
            case .autoReload, .postContest:
                return "changes the configuration"
            }
        case .appAction(let action):
            switch action {
            case .debugCat, .reopen:
                return nil
            case .broadcastLog, .exit, .exitNow, .wipeLogNow, .closeContest, .newContest, .openContest, .copyLog,
                 .reload, .resetInterfaces, .loadBeacons, .logout:
                return notFromPlugins
            }
        case .esmOn:
            return "ESM transmits on Enter"
        case .spotMe:
            return "spots go to the public network (use spots.send)"
        case .runScript:
            return "scripts are not run from plugins"
        case .wipeLog:
            return "destroys data"
        case .networkOn, .networkOff:
            return "network services are not switched from plugins"
        case .login, .autoRunSp, .setTour, .tourOff, .bonusStations, .roverQth, .countyLine, .countyLineOff,
             .cutNumbers, .openSettingsTab, .openSetup, .exportAdif, .exportCabrillo, .importLog:
            return notFromPlugins
        case .invalid(let message):
            return message
        }
    }
}
