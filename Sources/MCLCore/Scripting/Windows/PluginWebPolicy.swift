import Foundation

/// What a plugin's web window may load and who may talk to the app.
///
/// - The page is served by the app under its own scheme (`mcl-plugin://local/<path>`), only from the plugin
///   directory (symbolic links resolved), with a strict `Content-Security-Policy` header: scripts only from the
///   page's own origin (no inline scripts unless the manifest opts in and the plugin holds neither `transmit` nor
///   `cat`), no plugins or frames from elsewhere, `connect`/`img` to the manifest's `webHosts` over `https` only.
/// - The main frame never leaves the plugin's scheme; subframes and subresources may load the plugin's files,
///   `data:`/`blob:` resources, and `https` from the listed hosts. A WebKit content rule list blocks the rest.
/// - Only the main frame of a plugin page may send requests to the app.
public enum PluginWebPolicy {

    public static let scheme = "mcl-plugin"
    public static let host = "local"

    /// The URL of a page (a path relative to the plugin directory).
    public static func pageURL(_ page: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + page
        return components.url
    }

    /// The file a plugin URL names, inside `directory` (symbolic links resolved); `nil` for anything else.
    public static func file(for url: URL, directory: String) -> URL? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host else { return nil }
        let relative: String = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        guard !relative.isEmpty, !relative.split(separator: "/").contains("..") else { return nil }
        let root: String = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath().path
        let target: URL = URL(fileURLWithPath: root).appendingPathComponent(relative).standardizedFileURL
            .resolvingSymlinksInPath()
        guard target.path.hasPrefix(root + "/") else { return nil }
        return target
    }

    /// The navigation rule: the main frame stays on the plugin's own pages; a subframe may also show `https` from
    /// a listed host. Never `data:`, `blob:`, `javascript:`, `file:` or another scheme for a navigation.
    public static func allowsNavigation(_ url: URL, mainFrame: Bool, directory: String, hosts: [String]) -> Bool {
        if file(for: url, directory: directory) != nil {
            return true
        }
        if mainFrame {
            return false
        }
        if url.absoluteString == "about:blank" {
            return true
        }
        return isListedHttps(url, hosts: hosts)
    }

    /// The subresource rule (what the content rule list lets through): the plugin's files, `data:`/`blob:`, and
    /// `https` from a listed host.
    public static func allowsLoad(_ url: URL, directory: String, hosts: [String]) -> Bool {
        if file(for: url, directory: directory) != nil {
            return true
        }
        switch url.scheme?.lowercased() {
        case "data", "blob":
            return true
        default:
            return isListedHttps(url, hosts: hosts)
        }
    }

    /// Whether a message from a frame may reach the app: only the main frame of a plugin page.
    public static func acceptsMessage(mainFrame: Bool, originScheme: String, originHost: String) -> Bool {
        mainFrame && originScheme.lowercased() == scheme && originHost.lowercased() == host
    }

    static func isListedHttps(_ url: URL, hosts: [String]) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return hosts.contains { allowed in
            let allowed = allowed.lowercased()
            return host == allowed || host.hasSuffix("." + allowed)
        }
    }

    /// The `Content-Security-Policy` of plugin pages.
    public static func contentSecurityPolicy(hosts: [String], inlineScripts: Bool) -> String {
        let remote: String = hosts.map { " https://" + $0 + " https://*." + $0 }.joined()
        let script: String = "script-src 'self'" + (inlineScripts ? " 'unsafe-inline'" : "")
        return "default-src 'self'; " + script + "; object-src 'none'; base-uri 'none'; form-action 'none'; "
            + "frame-src 'self'" + remote + "; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:" + remote
            + "; connect-src 'self'" + remote + "; font-src 'self' data:"
    }

    /// The MIME type a served file gets (by its extension).
    public static func mimeType(_ file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }

    /// The WebKit content rule list (JSON): block every load, then let the plugin scheme, `data:`, `blob:` and
    /// `https` to the listed hosts through again.
    public static func contentRules(hosts: [String]) -> String {
        var rules: [PluginJSON] = [
            .object(["trigger": .object(["url-filter": .string(".*")]),
                     "action": .object(["type": .string("block")])]),
            .object(["trigger": .object(["url-filter": .string("^(" + scheme + "|data|blob):")]),
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

    /// The bridge script the page gets before it loads (only on plugin pages): `window.mcl.request(method,
    /// params)` (a promise of the result, rejected with `{code, message}`) and `window.mcl.on(event, handler)`. The
    /// app answers by `window.mcl._reply(id, answerJson)` and delivers events by `window.mcl._receive(eventJson)`.
    public static let bridgeScript: String = """
        (function () {
          if (location.protocol !== "\(scheme):") { return; }
          const handlers = {};
          const pending = {};
          let next = 0;
          const mcl = {
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
          Object.defineProperty(window, "mcl", { value: Object.freeze(mcl), writable: false, configurable: false });
        })();
        """
}
