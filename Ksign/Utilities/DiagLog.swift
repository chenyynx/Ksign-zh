//
//  DiagLog.swift
//  Ksign
//
//  轻量诊断日志：写到 Documents/ksign-diag.log，用来确认安装包实际的 plist 配置
//  以及文件是从哪条通道进来的（documentBrowser / openURLContexts / inboxScan）。
//  第三方签名工具会改写 UISupportsDocumentBrowser，构建包的值不代表安装包的值，
//  所以这里记录运行时读到的值。
//

import Foundation

enum DiagLog {
	private static let maxBytes = 256 * 1024

	static func logLaunchInfo() {
		let info = Bundle.main.infoDictionary ?? [:]
		let docBrowser = String(describing: info["UISupportsDocumentBrowser"] ?? "nil")
		let inPlace = String(describing: info["LSSupportsOpeningDocumentsInPlace"] ?? "nil")
		let types = (info["CFBundleDocumentTypes"] as? [[String: Any]] ?? [])
			.compactMap { $0["LSItemContentTypes"] as? [String] }
			.flatMap { $0 }
		log("launch: DocBrowser=\(docBrowser) InPlace=\(inPlace) types=\(types)")
	}

	static func log(_ message: String) {
		print("[KsignDiag] \(message)")

		let line = "\(timestamp()) \(message)\n"
		guard let data = line.data(using: .utf8) else { return }

		let fileManager = FileManager.default
		let file = URL.documentsDirectory.appendingPathComponent("ksign-diag.log")

		if
			let attributes = try? fileManager.attributesOfItem(atPath: file.path),
			let size = attributes[.size] as? Int,
			size > maxBytes
		{
			try? fileManager.removeItem(at: file)
		}

		if let handle = try? FileHandle(forWritingTo: file) {
			defer { try? handle.close() }
			handle.seekToEndOfFile()
			handle.write(data)
		} else {
			try? data.write(to: file)
		}
	}

	private static func timestamp() -> String {
		ISO8601DateFormatter().string(from: Date())
	}
}
