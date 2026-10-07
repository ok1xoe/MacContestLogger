import AppKit
import MCLAppModel
import MCLCore
import SwiftUI
import WebKit

/// A plugin's web window: its own HTML page in a `WKWebView`, served by the app under `mcl-plugin://local/` from the
/// plugin directory with a strict Content-Security-Policy header (`PluginWebPolicy`). The page talks to the app
/// through `window.mcl` (the bridge script): requests with the plugin's permissions and the subscribed events — only
/// from the main frame of a plugin page. Loads are limited by a content rule list, every navigation is checked (the
/// main frame never leaves the plugin's pages), there are no popups and no kept website data. The window's font
/// stepper sets the page zoom.
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
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(context.coordinator.files, forURLScheme: PluginWebPolicy.scheme)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
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

    /// Serves the plugin's files with the page's CSP; anything outside the plugin directory is 404.
    final class PluginFiles: NSObject, WKURLSchemeHandler {
        private let directory: String
        private let policy: String

        init(directory: String, policy: String) {
            self.directory = directory
            self.policy = policy
        }

        func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
            guard let url = task.request.url else { return }
            guard let file = PluginWebPolicy.file(for: url, directory: directory),
                  let data = try? Data(contentsOf: file) else {
                let missing = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])
                if let missing {
                    task.didReceive(missing)
                }
                task.didFinish()
                return
            }
            let headers: [String: String] = [
                "Content-Type": PluginWebPolicy.mimeType(file), "Content-Security-Policy": policy,
                "X-Content-Type-Options": "nosniff", "Cache-Control": "no-store",
            ]
            if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                              headerFields: headers) {
                task.didReceive(response)
            }
            task.didReceive(data)
            task.didFinish()
        }

        func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        private let app: AppModel
        private let key: String
        let files: PluginFiles
        private let setup: PluginWindowsModel.WebSetup?
        private weak var view: WKWebView?
        private var listener: Int?

        init(app: AppModel, key: String) {
            self.app = app
            self.key = key
            let setup: PluginWindowsModel.WebSetup? = app.pluginWindows.webSetup(key)
            self.setup = setup
            // Without a setup nothing is served at all.
            files = PluginFiles(directory: setup?.directory ?? "/nonexistent",
                                policy: setup?.contentSecurityPolicy ?? "default-src 'none'")
        }

        func attach(_ view: WKWebView) {
            self.view = view
            guard let setup, let page = PluginWebPolicy.pageURL(setup.page) else { return }
            listener = app.pluginWindows.addWebListener(key) { [weak self] line in
                MainHop.post {
                    self?.deliver(line)
                }
            }
            let rules: String = PluginWebPolicy.contentRules(hosts: setup.hosts)
            let identifier: String = "mcl-plugin-" + String(key.unicodeScalars.filter { $0.isASCII && $0 != "/" && $0 != ":" })
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier,
                                                                    encodedContentRuleList: rules) { list, _ in
                MainActor.assumeIsolated {
                    guard let view = self.view else { return }
                    // Without the rule list nothing is loaded at all (no page with unrestricted loads).
                    guard let list else { return }
                    view.configuration.userContentController.add(list)
                    view.load(URLRequest(url: page))
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
            // Only the main frame of a plugin page talks to the app (never a subframe, never another origin).
            let origin: WKSecurityOrigin = message.frameInfo.securityOrigin
            guard PluginWebPolicy.acceptsMessage(mainFrame: message.frameInfo.isMainFrame,
                                                 originScheme: origin.protocol, originHost: origin.host),
                  JSONSerialization.isValidJSONObject(message.body),
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
            guard let setup, let url = navigationAction.request.url,
                  PluginWebPolicy.allowsNavigation(url, mainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
                                                   directory: setup.directory, hosts: setup.hosts) else {
                return .cancel
            }
            return .allow
        }

        /// No popups, no new windows.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}
