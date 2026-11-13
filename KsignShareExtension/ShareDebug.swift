//
//  ShareDebug.swift
//  KsignShareExtension
//

import Foundation

enum ShareDebug {
	static func log(_ message: String) {
		let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
		guard let root = SharedContainer.root else { return }
		let url = root.appendingPathComponent("diag-ext.log")
		if let data = line.data(using: .utf8) {
			if FileManager.default.fileExists(atPath: url.path),
			   let handle = try? FileHandle(forWritingTo: url) {
				_ = try? handle.seekToEnd()
				try? handle.write(contentsOf: data)
				try? handle.close()
			} else {
				try? data.write(to: url, options: .atomic)
			}
		}
	}
}
