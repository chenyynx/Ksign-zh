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

	/// 递归统计占用（用于日志里确认清理效果）。
	static func allocatedSize(of url: URL) -> Int64 {
		let fileManager = FileManager.default
		var isDirectory: ObjCBool = false
		guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
			return 0
		}

		if !isDirectory.boolValue {
			let attributes = try? fileManager.attributesOfItem(atPath: url.path)
			return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
		}

		let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
		guard let enumerator = fileManager.enumerator(
			at: url,
			includingPropertiesForKeys: keys,
			options: [],
			errorHandler: nil
		) else {
			return 0
		}

		var total: Int64 = 0
		for case let item as URL in enumerator {
			guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
			total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
		}
		return total
	}

	/// 清空扩展自己的 tmp 里超过 minimumAge 的文件。
	/// 分享导入会先把文件复制到 tmp 再复制进共享目录，旧版本复制完不删；
	/// 扩展启动时清一遍历史遗留。只删旧文件，避免误删本次正在用的中转副本。
	@discardableResult
	static func purgeTemporaryDirectory(minimumAge: TimeInterval = 3600) -> Int64 {
		let fileManager = FileManager.default
		let tmp = fileManager.temporaryDirectory
		guard let items = try? fileManager.contentsOfDirectory(
			at: tmp,
			includingPropertiesForKeys: [.contentModificationDateKey],
			options: []
		) else {
			return 0
		}

		var freed: Int64 = 0
		for item in items {
			let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
			guard Date().timeIntervalSince(modified) >= minimumAge else { continue }
			freed += allocatedSize(of: item)
			try? fileManager.removeItem(at: item)
		}
		return freed
	}
}
