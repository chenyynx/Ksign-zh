//
//  SharedContainer.swift
//  KsignShareExtension
//
//  主 App 与分享扩展之间的共享目录。
//  描述文件提供的 App Group 不一定是我们想要的那个，
//  所以按候选列表逐个尝试，取第一个可用的容器。
//

import Foundation

enum SharedContainer {
	/// 自己的 group 优先；后面几个是全能签签名时描述文件里实际带的 group，
	/// 第三方重签后通常只有这些可用。
	static let candidates: [String] = [
		"group.nya.asami.ksign",
		"group.a05b266105020512.2",
		"group.a05b266105020512.3",
		"group.a05b266105020512.5"
	]

	static var root: URL? {
		for identifier in candidates {
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
}
