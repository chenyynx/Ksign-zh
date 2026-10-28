//
//  URLRouter.swift
//  Ksign
//
//  统一处理外部 URL：分享 / “用其他应用打开” / 自定义 scheme。
//  Scene 生命周期下 application(_:open:) 不会被调用，.onOpenURL 是主路径；
//  另外 Documents/Inbox 里系统会放一份副本，作为冷启动兜底。
//

import Foundation
import UIKit

final class URLRouter {
	static let shared = URLRouter()
	private init() {}

	func handle(_ url: URL) {
		print("[URLRouter] received: \(url.absoluteString) ext=\(url.pathExtension)")

		if url.scheme == "ksign" {
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
			let didStart = url.startAccessingSecurityScopedResource()
			print("[URLRouter] importing \(url.lastPathComponent) scope=\(didStart)")

			FR.handlePackageFile(url) { error in
				if didStart {
					url.stopAccessingSecurityScopedResource()
				}

				if let error {
					print("[URLRouter] import failed: \(String(describing: error))")
					Self.present(
						title: "导入失败",
						message: "\(url.lastPathComponent)\n\n\(String(describing: error))"
					)
				} else {
					print("[URLRouter] import finished: \(url.lastPathComponent)")
				}
			}
			return
		}

		if ext == "ksign" {
			Self.present(
				title: "不支持的文件类型",
				message: "从 v1.5.1 起不再支持 .ksign 证书文件，请改用 .p12 和 .mobileprovision。"
			)
			return
		}

		print("[URLRouter] ignored unsupported url: \(url.absoluteString)")
	}

	/// 冷启动兜底：系统会把“用其他应用打开”的文件复制到 Documents/Inbox
	static func importInboxFiles() {
		let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
		guard let files = try? FileManager.default.contentsOfDirectory(
			at: inbox,
			includingPropertiesForKeys: nil
		) else {
			return
		}

		let candidates = files.filter {
			["ipa", "tipa"].contains($0.pathExtension.lowercased())
		}
		guard !candidates.isEmpty else { return }
		print("[URLRouter] inbox found \(candidates.count) file(s)")

		for file in candidates {
			shared.handle(file)
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
				print("[URLRouter] no presenter, alert skipped: \(title) / \(message)")
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
