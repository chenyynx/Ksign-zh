//
//  StorageJanitor.swift
//  Ksign
//
//  存储上限与自动清理。
//  超过上限时按「最没用 / 最旧」的顺序逐项清理：
//  导出存档（最旧优先）→ 缓存与临时文件 → 下载原包（最旧优先）→ 已签名应用（最旧优先）。
//  不动已下载应用（原始素材）和证书。
//

import Foundation
import CoreData

// MARK: - 占用统计

enum StorageFootprint {
	/// 递归统计目录（或单个文件）的已分配大小。
	static func allocatedSize(of url: URL?) -> Int64 {
		guard let url else { return 0 }

		let fileManager = FileManager.default
		var isDirectory: ObjCBool = false
		guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
			return 0
		}

		if !isDirectory.boolValue {
			let attributes = try? fileManager.attributesOfItem(atPath: url.path)
			return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
		}

		let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
		guard let enumerator = fileManager.enumerator(
			at: url,
			includingPropertiesForKeys: Array(keys),
			options: [],
			errorHandler: nil
		) else {
			return 0
		}

		var total: Int64 = 0
		for case let item as URL in enumerator {
			guard let values = try? item.resourceValues(forKeys: keys) else { continue }
			total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
		}
		return total
	}

	/// Ksign 整体占用：Documents + Library + tmp，对齐 iOS「文稿与数据」的口径。
	static func appTotalBytes() -> Int64 {
		let documents = URL.documentsDirectory
		let library = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
		return allocatedSize(of: documents)
			+ allocatedSize(of: library)
			+ allocatedSize(of: FileManager.default.temporaryDirectory)
	}
}

// MARK: - 自动清理

enum StorageJanitor {
	static let limitDefaultsKey = "Feather.storageLimitGB"

	static var limitBytes: Int64 {
		Int64(UserDefaults.standard.integer(forKey: limitDefaultsKey)) * 1024 * 1024 * 1024
	}

	private static let queue = DispatchQueue(label: "ksign.storage.janitor", qos: .utility)
	private static let lock = NSLock()

	/// 超过上限时清理到上限以下。
	/// - Parameter completion: 主线程回调，参数为实际释放的字节数。
	static func enforceIfNeeded(completion: ((Int64) -> Void)? = nil) {
		guard limitBytes > 0 else {
			DispatchQueue.main.async { completion?(0) }
			return
		}

		queue.async {
			lock.lock()
			defer { lock.unlock() }

			let freed = _enforce(limit: limitBytes)
			if freed > 0 {
				DiagLog.log("auto-clean: freed \(freed) bytes, total now \(StorageFootprint.appTotalBytes()) (limit \(limitBytes))")
			}
			DispatchQueue.main.async { completion?(freed) }
		}
	}

	private static func _enforce(limit: Int64) -> Int64 {
		var total = StorageFootprint.appTotalBytes()
		guard total > limit else { return 0 }

		let fileManager = FileManager.default
		let documents = URL.documentsDirectory
		let applicationSupport = try? fileManager.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: false
		)

		var freed: Int64 = 0

		// 1) 导出存档：最旧优先；2 分钟内刚导出的保留，避免删掉正在分享给其他 App 的包。
		if total > limit {
			let amount = purgeOldestFiles(
				in: fileManager.archives,
				bytesNeeded: total - limit,
				minimumAge: 120
			)
			freed += amount
			total -= amount
		}

		// 2) 缓存与临时文件
		if total > limit {
			let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
			let before = StorageFootprint.allocatedSize(of: caches)
			ResetView.clearNetworkCache()
			let cacheFreed = max(0, before - StorageFootprint.allocatedSize(of: caches))
			freed += cacheFreed
			total -= cacheFreed

			// 保留 5 分钟内还在用的文件，避免打断正在进行的导入/签名。
			let tmpFreed = purgeOldestFiles(
				in: fileManager.temporaryDirectory,
				bytesNeeded: total - limit,
				minimumAge: 300
			)
			freed += tmpFreed
			total -= tmpFreed

			let resumeFreed = purgeOldestFiles(
				in: applicationSupport?.appendingPathComponent("ResumeData"),
				bytesNeeded: total - limit,
				minimumAge: 300
			)
			freed += resumeFreed
			total -= resumeFreed
		}

		// 3) 下载原包：最旧优先
		if total > limit {
			let amount = purgeOldestFiles(
				in: documents.appendingPathComponent("Downloads"),
				bytesNeeded: total - limit,
				minimumAge: 60
			)
			freed += amount
			total -= amount
		}

		// 4) 最旧的已签名应用；10 分钟内刚签的跳过，避免打断正在进行的操作。
		if total > limit {
			let amount = purgeOldestSignedApps(
				bytesNeeded: total - limit,
				minimumAge: 600
			)
			freed += amount
			total -= amount
		}

		return freed
	}

	/// 按修改时间从旧到新删，删够 bytesNeeded 就停。
	private static func purgeOldestFiles(in directory: URL?, bytesNeeded: Int64, minimumAge: TimeInterval) -> Int64 {
		guard let directory, bytesNeeded > 0 else { return 0 }

		let fileManager = FileManager.default
		let keys: Set<URLResourceKey> = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
		guard let items = try? fileManager.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: Array(keys),
			options: []
		) else {
			return 0
		}

		let sorted = items.sorted { lhs, rhs in
			let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
			let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
			return left < right
		}

		var freed: Int64 = 0
		for item in sorted {
			if freed >= bytesNeeded { break }

			let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
			if minimumAge > 0, Date().timeIntervalSince(modified) < minimumAge {
				continue
			}

			let size = StorageFootprint.allocatedSize(of: item)
			guard (try? fileManager.removeItem(at: item)) != nil else {
				continue
			}
			freed += size
		}
		return freed
	}

	/// 按 CoreData 里的签名日期从旧到新删除已签名应用。
	private static func purgeOldestSignedApps(bytesNeeded: Int64, minimumAge: TimeInterval) -> Int64 {
		guard bytesNeeded > 0 else { return 0 }

		var freed: Int64 = 0
		DispatchQueue.main.sync {
			let storage = Storage.shared
			let request = Signed.fetchRequest()
			request.sortDescriptors = [NSSortDescriptor(keyPath: \Signed.date, ascending: true)]
			let apps = (try? storage.context.fetch(request)) ?? []

			for app in apps {
				if freed >= bytesNeeded { break }
				if let date = app.date, minimumAge > 0, Date().timeIntervalSince(date) < minimumAge {
					continue
				}

				let size = storage.getUuidDirectory(for: app).map { StorageFootprint.allocatedSize(of: $0) } ?? 0
				storage.deleteApp(for: app)
				freed += size
			}

			if storage.context.hasChanges {
				try? storage.context.save()
			}
		}
		return freed
	}
}
