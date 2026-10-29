//
//  ShareViewController.swift
//  KsignShareExtension
//
//  分享面板入口：接收文件 → 展示确认界面 → 复制到 App Group 共享目录 → 唤起主 App 导入
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
	private let model = ShareImportModel()
	private var hosting: UIHostingController<ShareImportView>?

	override func viewDidLoad() {
		super.viewDidLoad()

		model.openHost = { [weak self] in
			guard let url = URL(string: "ksign://share-import") else { return }
			self?.extensionContext?.open(url, completionHandler: nil)
		}

		model.finish = { [weak self] success in
			if success {
				self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
			} else {
				self?.extensionContext?.cancelRequest(
					withError: NSError(domain: "ksign.share", code: 0)
				)
			}
		}

		let root = ShareImportView(model: model) { [weak self] in
			self?.extensionContext?.cancelRequest(
				withError: NSError(domain: "ksign.share.cancel", code: 0)
			)
		}

		let controller = UIHostingController(rootView: root)
		addChild(controller)
		controller.view.frame = view.bounds
		controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		view.addSubview(controller.view)
		controller.didMove(toParent: self)
		hosting = controller

		loadInputFiles()
	}

	private func loadInputFiles() {
		guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
			model.status = "没有收到任何内容"
			return
		}

		let providers = items.flatMap { $0.attachments ?? [] }
		guard !providers.isEmpty else {
			model.status = "没有收到任何文件"
			return
		}

		let group = DispatchGroup()

		for provider in providers {
			group.enter()
			load(from: provider) { [weak self] shared in
				DispatchQueue.main.async {
					if let shared {
						self?.model.files.append(shared)
					}
					group.leave()
				}
			}
		}

		group.notify(queue: .main) { [weak self] in
			guard let self else { return }
			if self.model.files.isEmpty {
				self.model.status = "这些内容不是可导入的文件（仅支持 .ipa / .tipa）"
			}
		}
	}

	private func load(from provider: NSItemProvider, completion: @escaping (SharedFile?) -> Void) {
		let identifiers = [
			"com.apple.itunes.ipa",
			UTType(filenameExtension: "ipa")?.identifier ?? "com.apple.itunes.ipa",
			UTType(filenameExtension: "tipa")?.identifier ?? "com.apple.itunes.ipa",
			UTType.item.identifier,
			UTType.data.identifier
		]

		guard let identifier = identifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
			completion(nil)
			return
		}

		provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
			guard let url else {
				completion(nil)
				return
			}

			// loadFileRepresentation 的 URL 在回调结束后失效，必须先拷进临时目录
			let temp = FileManager.default.temporaryDirectory
				.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
			do {
				try FileManager.default.copyItem(at: url, to: temp)
			} catch {
				completion(nil)
				return
			}

			let size = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int64) ?? 0
			completion(SharedFile(name: temp.lastPathComponent, url: temp, size: size))
		}
	}
}
