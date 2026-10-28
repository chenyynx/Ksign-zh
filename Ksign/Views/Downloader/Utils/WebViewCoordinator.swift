//
//  WebViewCoordinator.swift
//  Ksign
//
//  Created by Nagata Asami on 5/24/25.
//

import SwiftUI
import WebKit

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var parent: WebViewContainer
    
    init(_ parent: WebViewContainer) {
        self.parent = parent
        super.init()
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        if handleSpecialURL(url) {
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }
    
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }
    
    // MARK: - WKUIDelegate
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if handleSpecialURL(url) {
                return nil
            }
            webView.load(navigationAction.request)
        }
        return nil
    }
    
    private func handleSpecialURL(_ url: URL) -> Bool {
        if url.scheme == "itms-services" {
            parent.handleITMSURL(url)
            return true
        }
        
        if parent.downloadManager.isIPAFile(url) {
            parent.downloadDirectFile(url)
            return true
        }
        
        return false
    }
    
    private func handleNavigationError(_ error: Error) {
        
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        // 我们自己 decisionHandler(.cancel) 交给下载器时，WebKit 会抛 102（frame load
        // interrupted by policy change）。这是预期流程，不是错误，不能弹。
        // WebKitErrorDomain 的 102 = frameLoadInterruptedByPolicyChange，
        // 是上面 decisionHandler(.cancel) 主动取消导航的必然产物，不是真错误。
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            return
        }
        
        UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
    }
}
