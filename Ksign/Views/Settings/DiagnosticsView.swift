//
//  DiagnosticsView.swift
//  Ksign
//
//  文件打开链路的可视化取证：不依赖 stdout 日志。
//

import SwiftUI
import NimbleViews

struct DiagnosticsView: View {
	@AppStorage("diag.buildTag") private var buildTag: String = "-"
	@AppStorage("diag.lastURL") private var lastURL: String = "（尚未收到任何 URL）"
	@AppStorage("diag.lastResult") private var lastResult: String = "-"
	@State private var inboxFiles: [String] = []
	@State private var documentsFiles: [String] = []
	@State private var refreshedAt: Date = .init()
	@State private var logTail: String = ""

	var body: some View {
		NBList("诊断") {
			NBSection("构建") {
				row("标记", DiagnosticsView.buildIdentifier)
				row("说明", "用于确认当前安装的是哪一次构建")
			}

			NBSection("文件打开") {
				row("最近收到 URL", lastURL)
				row("最近结果", lastResult)
			}

			NBSection("文档配置（实际安装包）") {
				row("InPlace", Self.info("LSSupportsOpeningDocumentsInPlace"))
				row("DocBrowser", Self.info("UISupportsDocumentBrowser"))
				row("多场景", Self.sceneMultipleScenes)
				row("文档类型", Self.docTypes)
			} footer: {
				Text("用于确认装的是哪一套配置：上游官方是 InPlace=NO / DocBrowser=YES / 多场景=true / 只声明 nya.asami.ipa。")
			}

			NBSection("diag.log 最近 40 行") {
				Text(logTail.isEmpty ? "（暂无日志）" : logTail)
					.font(.system(size: 10, design: .monospaced))
					.textSelection(.enabled)
			} footer: {
				Text("文件位置：文件 App → 我的 iPhone → Ksign → diag.log")
			}

			NBSection("Documents（手动放置也可导入）") {
				if documentsFiles.isEmpty {
					Text("暂无 IPA").foregroundColor(.secondary)
				} else {
					ForEach(documentsFiles, id: \.self) { name in
						Text(name).font(.footnote)
					}
				}
			} footer: {
				Text("把 IPA 拷到「文件 App → 我的 iPhone → Ksign」，回到 App 即会自动导入。")
			}

			NBSection("Documents/Inbox") {
				if inboxFiles.isEmpty {
					Text("暂无文件")
						.foregroundColor(.secondary)
				} else {
					ForEach(inboxFiles, id: \.self) { name in
						Text(name).font(.footnote)
					}
				}

				Button {
					URLRouter.importInboxFiles()
					refresh()
				} label: {
					Label("重新扫描 Inbox", systemImage: "arrow.clockwise")
				}
			} footer: {
				Text("系统把「用其他应用打开」的文件复制到 Documents/Inbox；这里可手动触发扫描。")
			}
		}
		.onAppear { refresh() }
		.refreshable { refresh() }
	}

	static let buildIdentifier = "doris-zh+inplace-20261029-k"

	static func info(_ key: String) -> String {
		"\(Bundle.main.infoDictionary?[key] ?? "nil")"
	}

	static var sceneMultipleScenes: String {
		guard
			let manifest = Bundle.main.infoDictionary?["UIApplicationSceneManifest"] as? [String: Any],
			let value = manifest["UIApplicationSupportsMultipleScenes"]
		else { return "nil" }
		return "\(value)"
	}

	static var docTypes: String {
		guard let types = Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]] else {
			return "nil"
		}
		return types.map { entry in
			let items = (entry["LSItemContentTypes"] as? [String])?.joined(separator: ",") ?? "-"
			let name = entry["CFBundleTypeName"] as? String ?? "-"
			return "\(name): \(items)"
		}.joined(separator: "\n")
	}

	private func refresh() {
		let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
		inboxFiles = (try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []

		let docs = URL.documentsDirectory
		let docsItems = (try? FileManager.default.contentsOfDirectory(atPath: docs.path)) ?? []
		documentsFiles = docsItems.filter { ["ipa", "tipa"].contains(($0 as NSString).pathExtension.lowercased()) }

		let logURL = URL.documentsDirectory.appendingPathComponent("diag.log")
		if let content = try? String(contentsOf: logURL, encoding: .utf8) {
			logTail = content.split(separator: "\n").suffix(40).joined(separator: "\n")
		}
		refreshedAt = Date()
	}

	@ViewBuilder
	private func row(_ title: String, _ value: String) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title).font(.caption).foregroundColor(.secondary)
			Text(value).font(.footnote)
		}
	}
}
