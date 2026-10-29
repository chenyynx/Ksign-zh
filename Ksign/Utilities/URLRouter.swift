//
//  URLRouter.swift
//  Ksign
//
//  统一处理外部 URL：分享 / “用其他应用打开” / 自定义 scheme。
//
//  文件打开有两条通道，必须都活着：
//  ① 系统投递 URL（onOpenURL / launchOptions / scene openURLContexts）
//  ② 系统把文件复制进 Documents/Inbox（LSSupportsOpeningDocumentsInPlace=NO 时）
//  ②是兜底：URL 通道受场景生命周期影响，可能整条丢失，Inbox 不会。
//  两条通道会指向同一个文件，所以这里用「文件名+大小」做去重。
//

import Foundation
import UIKit

final class URLRouter {
	static let shared = URLRouter()

	/// 已经处理完的（或正在处理的）文件，避免 URL 与 Inbox 双通道重复导入
	private let _lock = NSLock()
	private var _handled: Set<String> = []
	private var _inFlight: Set<String> = []

	private init() {}

	func handle(_ url: URL, removeSource: Bool = false) {
		DiagLog.write("URLRouter.handle \(url.absoluteString) ext=\(url.pathExtension)")
		UserDefaults.standard.set("\(url.absoluteString)\n(ext=\(url.pathExtension))", forKey: "diag.lastURL")

		if url.scheme == "ksign" {
			if url.host == "share-import" || url.absoluteString.contains("share-import") {
				DiagLog.write("URLRouter: share-import trigger")
				Self.importSharedInbox()
				return
			}

			if let fullPath = url.validatedScheme(after: "/source/") {
				FR.handleSource(fullPath) { }
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

		let ext = url.pathExtension.lowercased()
		if ext == "ipa" || ext == "tipa" {
			_import(url, removeSource: removeSource)
			return
		}

		if ext == "ksign" {
			Self.present(
				title: "不支持的文件类型",
				message: "从 v1.5.1 起不再支持 .ksign 证书文件，请改用 .p12 和 .mobileprovision。"
			)
			return
		}

		DiagLog.write("URLRouter: ignored unsupported url \(url.absoluteString)")
	}

	// MARK: - 导入

	private func _import(_ url: URL, removeSource: Bool) {
		let key = _key(for: url)

		_lock.lock()
		let alreadyDone = _handled.contains(key)
		let running = _inFlight.contains(key)
		if !alreadyDone && !running {
			_inFlight.insert(key)
		}
		_lock.unlock()

		if running {
			// 同一文件正在导入，别打断，也别删（源文件还在被读）
			return
		}
		if alreadyDone {
			// 之前已经导过一次（同一文件经 URL 与 Inbox 两条通道到达），
			// 这里只负责把 Inbox 里残留的副本清掉。
			DiagLog.write("URLRouter: skip duplicate \(key)")
			if removeSource {
				try? FileManager.default.removeItem(at: url)
			}
			return
		}

		// 无条件尝试取 scope：返回 false 只代表「不是 security-scoped URL」，
		// 不代表不能读。不能因为 false 就放弃（历史 bug：静默 return）。
		let didStart = url.startAccessingSecurityScopedResource()
		DiagLog.write("import start \(url.lastPathComponent) scope=\(didStart)")

		let item = ExtractManager.shared.start(fileName: url.lastPathComponent)

		// 导入是纯 CPU/IO 的后台任务，用户切走 App 时不能让系统把进程挂起
		let bgTask = UIApplication.shared.beginBackgroundTask(withName: "ksign-import", expirationHandler: nil)

		FR.handlePackageFile(url, progress: { value in
			ExtractManager.shared.updateProgress(for: item, progress: value)
		}) { error in
			if didStart {
				url.stopAccessingSecurityScopedResource()
			}

			ExtractManager.shared.finish(item: item)

			if bgTask != .invalid {
				UIApplication.shared.endBackgroundTask(bgTask)
			}

			self._lock.lock()
			self._inFlight.remove(key)
			if error == nil {
				self._handled.insert(key)
			}
			self._lock.unlock()

			// Inbox 里的副本导入完就删掉，否则会被反复扫到
			if removeSource {
				try? FileManager.default.removeItem(at: url)
			}

			if let error {
				DiagLog.write("import failed \(url.lastPathComponent): \(error)")
				UserDefaults.standard.set("失败：\(String(describing: error))", forKey: "diag.lastResult")
				Self.present(
					title: "导入失败",
					message: "\(url.lastPathComponent)\n\n\(String(describing: error))"
				)
			} else {
				DiagLog.write("import success \(url.lastPathComponent)")
				UserDefaults.standard.set("成功：\(url.lastPathComponent)", forKey: "diag.lastResult")
			}
		}
	}

	private func _key(for url: URL) -> String {
		let name = url.lastPathComponent.lowercased()
		let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
		return "\(name)#\(size)"
	}

	// MARK: - 兜底入口

	/// 分享扩展写入 App Group 的文件：先搬到沙盒临时目录再导入，避免异步读取时源文件被清理
	static func importSharedInbox() {
		SharedInbox.drain { file in
			let temp = FileManager.default.temporaryDirectory
				.appendingPathComponent("\(UUID().uuidString)-\(file.lastPathComponent)")
			do {
				try FileManager.default.copyItem(at: file, to: temp)
				try? FileManager.default.removeItem(at: file)
				shared.handle(temp, removeSource: true)
			} catch {
				DiagLog.write("SharedInbox copy failed: \(error.localizedDescription)")
			}
		}
	}

	/// 冷启动兜底：LSSupportsOpeningDocumentsInPlace=NO 时，系统会把
	/// 「用其他应用打开」的文件复制到 Documents/Inbox。
	static func importInboxFiles() {
		let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)

		guard let files = try? FileManager.default.contentsOfDirectory(
			at: inbox,
			includingPropertiesForKeys: [.fileSizeKey],
			options: [.skipsHiddenFiles]
		) else {
			return
		}

		let candidates = files.filter {
			["ipa", "tipa"].contains($0.pathExtension.lowercased())
		}
		guard !candidates.isEmpty else { return }

		DiagLog.write("Inbox scan: \(candidates.count) candidate(s) \(candidates.map(\.lastPathComponent))")

		for file in candidates {
			shared.handle(file, removeSource: true)
		}
	}

	/// 不自带 presenter 强解包，避免启动瞬间没有 topViewController 时静默失败
	static func present(title: String, message: String) {
		DispatchQueue.main.async {
			let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
			let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first

			guard
				let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
					?? scene?.windows.first?.rootViewController
			else {
				DiagLog.write("present skipped (no presenter): \(title) / \(message)")
				return
			}

			var top = root
			while let presented = top.presentedViewController {
				top = presented
			}

			let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: "OK", style: .default))
			top.present(alert, animated: true)
		}
	}
}
