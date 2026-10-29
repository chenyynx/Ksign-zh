//
//  DiagLog.swift
//  Ksign
//
//  把生命周期与 URL 回调按时间写进 Documents/diag.log，
//  不依赖 stdout 捕获、不依赖 UI，事后可直接在「文件」App 里查看。
//

import Foundation

enum DiagLog {
	private static let fileURL: URL = {
		URL.documentsDirectory.appendingPathComponent("diag.log")
	}()

	private static let formatter: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "HH:mm:ss.SSS"
		return f
	}()

	static func write(_ message: String) {
		let line = "[\(formatter.string(from: Date()))] \(message)\n"

		if let data = line.data(using: .utf8) {
			if FileManager.default.fileExists(atPath: fileURL.path),
			   let handle = try? FileHandle(forWritingTo: fileURL) {
				_ = try? handle.seekToEnd()
				try? handle.write(contentsOf: data)
				try? handle.close()
			} else {
				try? data.write(to: fileURL, options: .atomic)
			}
		}

		print(line, terminator: "")
	}

	static func resetIfNeeded() {
		// 每次冷启动另起一段，但保留历史，方便对比
		write("==== app launched ====")
	}
}
