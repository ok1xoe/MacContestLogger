import Foundation

/// What a plugin's web window may load. The page and everything it references come from the plugin directory
/// (`file:`); a remote load is allowed only over `https` to a host the manifest lists in `webHosts` (or a subdomain
/// of one); every other scheme is blocked. The same rules are given to WebKit as a content rule list (blocking
/// subresources) and checked for every navigation.
public enum PluginWebPolicy {

    /// Whether `url` may be loaded by the web window of the plugin in `directory`.
    public static func allows(_ url: URL, directory: String, hosts: [String]) -> Bool {
        switch url.scheme?.lowercased() {
        case "file":
            let root: String = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath().path
            let path: String = url.standardizedFileURL.resolvingSymlinksInPath().path
            return path == root || path.hasPrefix(root + "/")
        case "https":
            guard let host = url.host?.lowercased() else { return false }
            return hosts.contains { allowed in
                let allowed = allowed.lowercased()
                return host == allowed || host.hasSuffix("." + allowed)
            }
        case "about":
            return url.absoluteString == "about:blank"
        case "data", "blob":
            // Inline images and blobs the page made itself.
            return true
        default:
            return false
        }
    }

    /// The WebKit content rule list (JSON): block every load whose scheme is not `file`, `data`, `blob` or `about`,
    /// then allow `https` to the listed hosts again.
    public static func contentRules(hosts: [String]) -> String {
        var rules: [PluginJSON] = [
            .object(["trigger": .object(["url-filter": .string(".*")]),
                     "action": .object(["type": .string("block")])]),
            .object(["trigger": .object(["url-filter": .string("^(file|data|blob|about):")]),
                     "action": .object(["type": .string("ignore-previous-rules")])]),
        ]
        for host in hosts {
            let escaped: String = host.lowercased().replacingOccurrences(of: ".", with: "\\.")
            rules.append(.object([
                "trigger": .object(["url-filter": .string("^https://([a-z0-9-]+\\.)*" + escaped + "(:[0-9]+)?(/|$)")]),
                "action": .object(["type": .string("ignore-previous-rules")]),
            ]))
        }
        return PluginJSON.array(rules).serialized()
    }

    /// The bridge script the page gets before it loads: `window.mcl.request(method, params)` (a promise of the
    /// result, rejected with `{code, message}`) and `window.mcl.on(event, handler)`. The app answers a request by
    /// `window.mcl._reply(id, answerJson)` and delivers events by `window.mcl._receive(eventJson)`.
    public static let bridgeScript: String = """
        (function () {
          const handlers = {};
          const pending = {};
          let next = 0;
          window.mcl = {
            protocol: 1,
            request: function (method, params) {
              next += 1;
              const id = next;
              return new Promise(function (resolve, reject) {
                pending[id] = { resolve: resolve, reject: reject };
                window.webkit.messageHandlers.mcl.postMessage({ id: id, method: method, params: params || {} });
              });
            },
            on: function (event, handler) {
              (handlers[event] = handlers[event] || []).push(handler);
            },
            _reply: function (id, line) {
              const waiting = pending[id];
              if (!waiting) { return; }
              delete pending[id];
              let answer;
              try { answer = JSON.parse(line); } catch (e) { waiting.reject({ code: "failed", message: "bad answer" }); return; }
              if (answer.error) { waiting.reject(answer.error); } else { waiting.resolve(answer.result); }
            },
            _receive: function (line) {
              let message;
              try { message = JSON.parse(line); } catch (e) { return; }
              if (message.type === "event") {
                (handlers[message.event] || []).forEach(function (h) { try { h(message.data); } catch (e) {} });
              }
            }
          };
        })();
        """
}
