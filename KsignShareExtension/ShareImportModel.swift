//
//  ShareImportModel.swift
//  KsignShareExtension
//

import Foundation
import Combine

final class ShareImportModel: ObservableObject {
	@Published var files: [SharedFile] = []
	@Published var status: String = ""
	@Published var isImporting: Bool = false
	@Published var isDone: Bool = false

	var openHost: (() -> Void)?
	var finish: ((Bool) -> Void)?

	func startImport() {
		guard let inbox = SharedContainer.inbox else {
			status = "无法访问共享目录：描述文件没有授予 App Group 权限。"
			return
		}

		isImporting = true
		status = "正在复制文件…"

		let snapshot = files
		DispatchQueue.global(qos: .userInitiated).async {
			var copied = 0
			for file in snapshot {
				let destination = inbox.appendingPathComponent("\(UUID().uuidString)-\(file.name)")
				do {
					try FileManager.default.copyItem(at: file.url, to: destination)
					copied += 1
				} catch {
					// 单个文件失败不影响其余文件
				}
			}

			DispatchQueue.main.async {
				self.isImporting = false

				guard copied > 0 else {
					self.status = "导入失败：无法写入共享目录。"
					return
				}

				self.isDone = true
				self.status = ""

				// 尝试跳转（第三方签名下可能失败），但不依赖它
				self.openHost?()
			}
		}
	}
}
