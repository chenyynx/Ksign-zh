//
//  SceneDelegate.swift
//  Ksign
//
//  文件接收入口：主界面直接作 window 根控制器。
//  文件来源有三条：分享扩展（App Group）、openURL（分享/打开方式）、
//  Documents/Inbox 扫描。曾经用 UIDocumentBrowserViewController 作根来接收
//  「打开方式」投递，但系统从未回调且启动会闪它的「最近项目」页面，已移除。
//

import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?

	/// 已尝试导入过的 Inbox 文件，避免失败文件每次回前台都重复弹窗。
	private static var attemptedInboxFiles: Set<String> = []

	// MARK: - Scene lifecycle

	func scene(
		_ scene: UIScene,
		willConnectTo session: UISceneSession,
		options connectionOptions: UIScene.ConnectionOptions
	) {
		guard let windowScene = scene as? UIWindowScene else { return }

		let window = UIWindow(windowScene: windowScene)
		self.window = window

		let host = UIHostingController(rootView: RootView())

		// 主界面直接作根控制器。
		// 注：曾经用 UIDocumentBrowserViewController 作根来接收「打开方式」投递，
		// 但系统从未回调（documents 全来自分享扩展），而且启动时会闪一下它的
		// 「最近项目」页面，已经移除。文件接收走分享扩展 + openURL + Inbox 扫描。
		window.rootViewController = host
		window.makeKeyAndVisible()

		for context in connectionOptions.urlContexts {
			Self.handle(context.url, source: "launchURL")
		}

		Self.importSharedInbox()
	}

	func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
		for context in URLContexts {
			Self.handle(context.url, source: "openURLContexts")
		}
	}

	func sceneDidBecomeActive(_ scene: UIScene) {
		// 兜底：系统把文件复制到 Documents/Inbox 的情况。
		Self.importInboxFiles(source: "inboxScan")
		// 分享扩展落进 App Group 的文件。
		Self.importSharedInbox()
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

			// 分享扩展用 ksign://share-import 唤起主 App
			importSharedInbox()
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

		// 复用文件页那套顶部进度横幅（ExtractManager + ExtractHeaderView）
		let item = ExtractManager.shared.start(fileName: url.lastPathComponent)
		let startedAt = Date()

		FR.handlePackageFile(url, progress: { value in
			ExtractManager.shared.updateProgress(for: item, progress: value)
		}) { error in
			if didStart {
				url.stopAccessingSecurityScopedResource()
			}

			// 导入通常 1 秒内完成，最小展示 0.6 秒，避免进度条一闪而过
			let elapsed = Date().timeIntervalSince(startedAt)
			let delay = max(0, 0.6 - elapsed)
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				ExtractManager.shared.finish(item: item)
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

	/// 扫描分享扩展写进 App Group 的文件，导入后删除。
	/// 先把文件移出共享目录再异步导入，避免回前台重复扫描导致重复入库。
	static func importSharedInbox() {
		SharedInbox.mergeExtensionDiagnostics()

		let count = SharedInbox.drain { url in
			let temp = FileManager.default.temporaryDirectory
				.appendingPathComponent("share-\(UUID().uuidString)-\(url.lastPathComponent)")
			guard (try? FileManager.default.moveItem(at: url, to: temp)) != nil else {
				DiagLog.log("shareInbox: move failed \(url.lastPathComponent)")
				return
			}
			DiagLog.log("shareInbox file: \(temp.lastPathComponent)")
			importFile(temp, source: "shareInbox", deleteAfterSuccess: true)
		}

		if count > 0 {
			DiagLog.log("shareInbox: draining \(count) file(s)")
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

