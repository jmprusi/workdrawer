//
//  WebPreviewView.swift
//  WorkDrawer
//
//  Created by Joaquim Moreno Prusi on 16/2/26.
//

import SwiftUI
import WebKit

struct WebPreviewView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var fontFamily: String
    var searchText: String = ""

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "checkbox")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let c = context.coordinator

        if !c.hasLoaded {
            c.hasLoaded = true
            c.isPageReady = false
            c.pendingText = text
            c.pendingFontFamily = fontFamily
            c.pendingFontSize = fontSize
            loadPage(in: webView)
            return
        }

        if !c.isPageReady {
            c.pendingText = text
            c.pendingFontFamily = fontFamily
            c.pendingFontSize = fontSize
            return
        }

        let fontChanged = c.lastFontSize != fontSize || c.lastFontFamily != fontFamily
        let textChanged = c.lastText != text

        if fontChanged {
            c.lastFontFamily = fontFamily
            c.lastFontSize = fontSize
            let familyJSON = encoded(fontFamily)
            webView.evaluateJavaScript("updateStyles(\(familyJSON), \(Int(fontSize)))", completionHandler: nil)
        }

        if textChanged {
            c.lastText = text
            let markdownJSON = encoded(text)
            let indicesJSON = encoded(checkboxLineIndices())
            webView.evaluateJavaScript("updateContent(\(markdownJSON), \(indicesJSON))", completionHandler: nil)
        }

        let searchChanged = c.lastSearchText != searchText
        if searchChanged || (textChanged && !searchText.isEmpty) {
            c.lastSearchText = searchText
            if searchText.isEmpty {
                webView.evaluateJavaScript("document.getSelection().removeAllRanges()", completionHandler: nil)
            } else {
                let encodedSearch = encoded(searchText)
                webView.evaluateJavaScript("document.getSelection().removeAllRanges(); window.find(\(encodedSearch), false, false, true)", completionHandler: nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func loadPage(in webView: WKWebView) {
        guard let url = Bundle.main.url(forResource: "preview", withExtension: "html") else { return }
        let bundleURL = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: bundleURL)
    }

    private func checkboxLineIndices() -> [Int] {
        text.components(separatedBy: .newlines).enumerated().compactMap { i, line in
            (line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ")) ? i : nil
        }
    }

    private func encoded(_ value: some Encodable) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "null"
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: WebPreviewView
        var hasLoaded = false
        var isPageReady = false
        var lastText = ""
        var lastFontSize: CGFloat = 0
        var lastFontFamily = ""
        var pendingText = ""
        var pendingFontSize: CGFloat = 14
        var pendingFontFamily = ""
        var lastSearchText = ""

        init(_ parent: WebPreviewView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageReady = true
            lastText = pendingText
            lastFontSize = pendingFontSize
            lastFontFamily = pendingFontFamily

            let familyJSON = encode(pendingFontFamily)
            let markdownJSON = encode(pendingText)
            let indicesJSON = encode(parent.checkboxLineIndices())
            let js = "init(\(familyJSON), \(Int(pendingFontSize)), \(markdownJSON), \(indicesJSON))"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isPageReady = false
            hasLoaded = false
        }

        private func encode(_ value: some Encodable) -> String {
            (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "null"
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "checkbox", let idx = message.body as? Int, idx >= 0 else { return }
            var lines = parent.text.components(separatedBy: .newlines)
            guard idx < lines.count else { return }
            var line = lines[idx]
            if line.hasPrefix("- [ ] ") {
                line = "- [x] " + line.dropFirst(6)
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                line = "- [ ] " + line.dropFirst(6)
            }
            lines[idx] = line
            parent.text = lines.joined(separator: "\n")
        }
    }
}
