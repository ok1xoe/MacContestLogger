import Foundation

/// Which call-field text commands a plugin may run with the `app.command` permission (the `app.command` request).
/// Everything that can make the station transmit, reach a public network, run other scripts or destroy data is
/// refused: the plugin gets an error and nothing runs.
public enum PluginCommandPolicy {

    /// Why a command is refused (`nil` = allowed).
    public static func refusal(_ command: CallFieldCommand) -> String? {
        switch command {
        case .toggle(let setting, let on) where setting == .cqRepeat && on:
            return "CQ repeat transmits"
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
        case .appAction(let action):
            switch action {
            case .exit, .exitNow, .wipeLogNow, .resetInterfaces, .broadcastLog:
                return "not allowed from plugins"
            default:
                return nil
            }
        case .invalid(let message):
            return message
        default:
            return nil
        }
    }
}
