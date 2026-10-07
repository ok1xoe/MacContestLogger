import AppKit
import MCLAppModel
import MCLCore
import SwiftUI
import WebKit

/// A plugin's web window: its own HTML page from the plugin directory in a `WKWebView`. The page talks to the app
/// through `window.mcl` (the bridge script): requests with the plugin's permissions and the subscribed events.
/// Loads are limited by `PluginWebPolicy` (the plugin directory; `https` only to the manifest's `webHosts`), both as a
/// WebKit content rule list and for every navigation. The window's font stepper sets the page zoom.
struct PluginWebView: NSViewRepresentable {
    let app: AppModel
    let key: String
    let title: String
    @Environment(\.windowFontSize) private var windowSize

    func makeCoordinator() -> Coordinator {
        Coordinator(app: app, key: key)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: PluginWebPolicy.bridgeScript, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        controller.add(context.coordinator, contentWorld: .page, name: "mcl")
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setAccessibilityLabel(title)
        view.pageZoom = CGFloat(windowSize) / CGFloat(WindowFont.defaultSize)
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let zoom = CGFloat(windowSize) / CGFloat(WindowFont.defaultSize)
        if view.pageZoom != zoom {
            view.pageZoom = zoom
        }
        view.setAccessibilityLabel(title)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "mcl", contentWorld: .page)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let app: AppModel
        private let key: String
        private weak var view: WKWebView?
        private var listener: Int?

        init(app: AppModel, key: String) {
            self.app = app
            self.key = key
        }

        func attach(_ view: WKWebView) {
            self.view = view
            guard let page = app.pluginWindows.webPage(key) else { return }
            listener = app.pluginWindows.addWebListener(key) { [weak self] line in
                MainHop.post {
                    self?.deliver(line)
                }
            }
            let rules: String = PluginWebPolicy.contentRules(hosts: page.hosts)
            let identifier: String = "mcl-plugin-" + String(key.unicodeScalars.filter { $0.isASCII && $0 != "/" && $0 != ":" })
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier,
                                                                    encodedContentRuleList: rules) { list, _ in
                MainActor.assumeIsolated {
                    guard let view = self.view else { return }
                    // Without the rule list nothing is loaded at all (no page with unrestricted loads).
                    guard let list else { return }
                    view.configuration.userContentController.add(list)
                    view.loadFileURL(page.page, allowingReadAccessTo: page.directory)
                }
            }
        }

        func detach() {
            if let listener {
                app.pluginWindows.removeWebListener(listener)
            }
            listener = nil
        }

        private func deliver(_ line: String) {
            view?.callAsyncJavaScript("window.mcl && window.mcl._receive(line)", arguments: ["line": line],
                                      in: nil, in: .page, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard JSONSerialization.isValidJSONObject(message.body),
                  let data = try? JSONSerialization.data(withJSONObject: message.body),
                  let request = try? PluginJSON.parse(Array(data)), let id = request["id"]?.intValue else { return }
            guard let method = request["method"]?.stringValue else {
                reply(id, .object(["error": .object(["code": .string("invalid_params"),
                                                     "message": .string("a request needs a method")])]))
                return
            }
            let params: [String: PluginJSON] = request["params"]?.objectValue ?? [:]
            let model: PluginWindowsModel = app.pluginWindows
            let key: String = self.key
            Task { @MainActor [weak self] in
                let answer: PluginJSON = await model.webAnswer(key, method: method, params: params)
                self?.reply(id, answer)
            }
        }

        private func reply(_ id: Int64, _ answer: PluginJSON) {
            view?.callAsyncJavaScript("window.mcl && window.mcl._reply(id, line)",
                                      arguments: ["id": Int(id), "line": answer.serialized()],
                                      in: nil, in: .page, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
            -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, let page = app.pluginWindows.webPage(key),
                  PluginWebPolicy.allows(url, directory: page.directory.path, hosts: page.hosts) else {
                return .cancel
            }
            return .allow
        }
    }
}
