//
//  SharedInbox.swift
//  Ksign
//
//  读取分享扩展写进 App Group 的文件。
//  候选 group 与扩展侧保持一致：自己的 group 优先，其次用描述文件里实际带的那几个。
//

import Foundation

enum SharedInbox {
	static let groupCandidates: [String] = [
		"group.nya.asami.ksign",
		"group.a05b266105020512.2",
		"group.a05b266105020512.3",
		"group.a05b266105020512.5"
	]

	static var root: URL? {
		for identifier in groupCandidates {
			if let url = FileManager.default.containerURL(
				forSecurityApplicationGroupIdentifier: identifier
			) {
				return url
			}
		}
		return nil
	}

	static var inbox: URL? {
		guard let root else { return nil }
		let url = root.appendingPathComponent("ShareInbox", isDirectory: true)
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	/// 把共享目录里的文件逐个交给 handler，并保证在 handler 处理完后删除
	@discardableResult
	static func drain(handler: (URL) -> Void) -> Int {
		guard let inbox else {
			DiagLog.write("SharedInbox: no app group container")
			return 0
		}

		guard let files = try? FileManager.default.contentsOfDirectory(
			at: inbox,
			includingPropertiesForKeys: nil
		) else {
			return 0
		}

		let ipas = files.filter { ["ipa", "tipa"].contains($0.pathExtension.lowercased()) }
		DiagLog.write("SharedInbox: \(ipas.count) file(s) in \(inbox.path)")

		for file in ipas {
			handler(file)
		}
		return ipas.count
	}
}
