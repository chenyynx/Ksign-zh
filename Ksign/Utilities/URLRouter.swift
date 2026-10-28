//
//  URLRouter.swift
//  Ksign
//
//  统一处理外部 URL：分享/“用其他应用打开”/自定义 scheme。
//  SwiftUI 的 .onOpenURL 在冷启动时可能收不到（视图还没挂载就投递完了），
//  所以 AppDelegate 的 application(_:open:options:) 也要走同一条路径。
//

import Foundation
import UIKit

final class URLRouter {
	static let shared = URLRouter()
	private init() {}

	func handle(_ url: URL) {
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

		// 分享 / “用其他应用打开”进来的 URL 可能带 security scope，也可能不带。
		// 尽力取 scope，取不到也照样试；失败必须报错，不能静默。
		let ext = url.pathExtension.lowercased()
		if ext == "ipa" || ext == "tipa" {
			let didStart = url.startAccessingSecurityScopedResource()

			FR.handlePackageFile(url) { error in
				if didStart {
					url.stopAccessingSecurityScopedResource()
				}

				if let error {
					UIAlertController.showAlertWithOk(
						title: "导入失败",
						message: "\(url.lastPathComponent)\n\n\(String(describing: error))"
					)
				}
			}
			return
		}

		if ext == "ksign" {
			UIAlertController.showAlertWithOk(
				title: .localized("Error"),
				message: .localized("Ksign certificate file (.ksign) is now unsupported from v1.5.1, please refer to use .p12 and .mobileprovision instead.")
			)
		}
	}
}
