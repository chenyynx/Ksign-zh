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

			NBSection("diag.log 最近 40 行") {
				Text(logTail.isEmpty ? "（暂无日志）" : logTail)
					.font(.system(size: 10, design: .monospaced))
					.textSelection(.enabled)
			} footer: {
				Text("文件位置：文件 App → 我的 iPhone → Ksign → diag.log")
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

	static let buildIdentifier = "doris-zh+docfix-20261029"

	private func refresh() {
		let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
		inboxFiles = (try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []

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
