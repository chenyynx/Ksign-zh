//
//  SceneDelegate.swift
//  Ksign
//
//  文档投递入口：安装包被第三方签名工具强制写成 UISupportsDocumentBrowser=YES 时，
//  iOS 不会走 openURL、也不会复制 Documents/Inbox，而是把文件交给
//  UIDocumentBrowserViewController。因此 window 根控制器必须是文档浏览器，
//  主界面以覆盖层形式呈现，浏览器留在层级里接收投递。
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?

	private var browser: UIDocumentBrowserViewController?
	private var host: UIHostingController<RootView>?
	private let hostViewTag = 0x4B534947 // "KSIG"

	/// 已尝试导入过的 Inbox 文件，避免失败文件每次回前台都重复弹窗。
	private static var attemptedInboxFiles: Set<String> = []

	/// 与 Info.plist 里 UTExportedTypeDeclarations 声明的 UTI 保持一致。
	static var documentTypes: [UTType] {
		var types: [UTType] = []
		if let ipa = UTType("nya.asami.ipa") { types.append(ipa) }
		if let tipa = UTType("nya.asami.tipa") { types.append(tipa) }
		return types.isEmpty ? [.data] : types
	}

	// MARK: - Scene lifecycle

	func scene(
		_ scene: UIScene,
		willConnectTo session: UISceneSession,
		options connectionOptions: UIScene.ConnectionOptions
	) {
		guard let windowScene = scene as? UIWindowScene else { return }

		let window = UIWindow(windowScene: windowScene)
		self.window = window

		let browser = UIDocumentBrowserViewController(forOpening: Self.documentTypes)
		browser.delegate = self
		browser.allowsDocumentCreation = false
		browser.shouldShowFileExtensions = false
		self.browser = browser

		window.rootViewController = browser
		window.makeKeyAndVisible()

		// 立刻用主界面盖住浏览器 UI；browser 仍在 presenting 层级里接收文档投递。
		let host = UIHostingController(rootView: RootView())
		host.modalPresentationStyle = .fullScreen
		host.view.tag = hostViewTag
		self.host = host
		DispatchQueue.main.async {
			Self.presentHostIfNeeded(on: browser, host: host)
		}

		for context in connectionOptions.urlContexts {
			Self.handle(context.url, source: "launchURL")
		}
	}

	func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
		for context in URLContexts {
			Self.handle(context.url, source: "openURLContexts")
		}
	}

	func sceneDidBecomeActive(_ scene: UIScene) {
		// 首次 present 若因时序失败，回前台时补一次。
		if let browser, let host {
			Self.presentHostIfNeeded(on: browser, host: host)
		}
		// 兜底：DocBrowser=NO 的签名环境（或系统复制到 Inbox 的情况）。
		Self.importInboxFiles(source: "inboxScan")
	}

	// MARK: - Host presentation

	private static func presentHostIfNeeded(
		on browser: UIDocumentBrowserViewController,
		host: UIHostingController<RootView>,
		attempt: Int = 0
	) {
		guard browser.presentedViewController == nil else { return }

		// 浏览器可能还没挂到 window 上，过早 present 会丢；短暂重试。
		if browser.view.window == nil, attempt < 20 {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
				presentHostIfNeeded(on: browser, host: host, attempt: attempt + 1)
			}
			return
		}

		browser.present(host, animated: false)
	}

	// MARK: - URL / file handling

	static func handle(_ url: URL, source: String) {
		DiagLog.log("received URL [\(source)]: \(url.absoluteString)")

		if url.scheme == "ksign" {
			if let fullPath = url.validatedScheme(after: "/source/") {
				FR.handleSource(fullPath) { _ in }
			}

			if
				let fullPath = url.validatedScheme(after: "/install/"),
				let downloadURL = URL(string: fullPath)
			{
				_ = DownloadManager.shared.startDownload(
					from: downloadURL,
					id: "FeatherManualDownload_\(UUID().uuidString)"
				)
			}
			return
		}

		// 分享 / “用其他应用打开”进来的 URL 可能带 security scope，也可能不带。
		// 改成尽力取、取不到也照样试，失败必须报错。
		let ext = url.pathExtension.lowercased()
		if ext == "ipa" || ext == "tipa" {
			importFile(url, source: source)
			return
		}

		if ext == "ksign" {
			UIAlertController.showAlertWithOk(
				title: .localized("Error"),
				message: .localized("Ksign certificate file (.ksign) is now unsupported from v1.5.1, please refer to use .p12 and .mobileprovision instead.")
			)
		}
	}

	static func importFile(_ url: URL, source: String, deleteAfterSuccess: Bool = false) {
		let didStart = url.startAccessingSecurityScopedResource()

		FR.handlePackageFile(url) { error in
			if didStart {
				url.stopAccessingSecurityScopedResource()
			}

			if let error {
				DiagLog.log("import failed [\(source)] \(url.lastPathComponent): \(error)")
				UIAlertController.showAlertWithOk(
					title: "导入失败",
					message: String(describing: error)
				)
			} else {
				DiagLog.log("import ok [\(source)] \(url.lastPathComponent)")
				if deleteAfterSuccess {
					try? FileManager.default.removeItem(at: url)
				}
			}
		}
	}

	/// 扫描 Documents/Inbox：仅在系统把文件复制进来时才会有内容（DocBrowser=NO 环境）。
	static func importInboxFiles(source: String) {
		let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
		guard let files = try? FileManager.default.contentsOfDirectory(
			at: inbox,
			includingPropertiesForKeys: nil
		) else { return }

		for url in files where ["ipa", "tipa"].contains(url.pathExtension.lowercased()) {
			guard !attemptedInboxFiles.contains(url.path) else { continue }
			attemptedInboxFiles.insert(url.path)
			DiagLog.log("inbox file found: \(url.lastPathComponent)")
			importFile(url, source: source, deleteAfterSuccess: true)
		}
	}
}

// MARK: - UIDocumentBrowserViewControllerDelegate

extension SceneDelegate: UIDocumentBrowserViewControllerDelegate {
	func documentBrowser(
		_ controller: UIDocumentBrowserViewController,
		didPickDocumentsAt documentURLs: [URL]
	) {
		DiagLog.log("documentBrowser didPickDocumentsAt: \(documentURLs.map(\.lastPathComponent))")
		for url in documentURLs {
			Self.handle(url, source: "documentBrowser")
		}
	}

	func documentBrowser(
		_ controller: UIDocumentBrowserViewController,
		didRequestDocumentCreationWithHandler importHandler: @escaping (URL?, UIDocumentBrowserViewController.ImportMode) -> Void
	) {
		// Ksign 不创建文档，只接收外部投递。
		importHandler(nil, .none)
	}
}
