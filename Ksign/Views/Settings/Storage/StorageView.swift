//
//  StorageView.swift
//  Ksign
//
//  存储与清理：把各目录的实际占用摆出来，并支持逐项清理。
//  资源库只能删「已下载 / 已签名」两份副本，安装包、导出存档、缓存、
//  临时文件、断点续传这些都不在资源库管辖内，集中放在这里处理。
//

import SwiftUI
import NimbleViews

extension Notification.Name {
	static let ksignStorageCleared = Notification.Name("ksign.storageCleared")
}

// MARK: - 数据模型

private enum StorageKind: String {
	case unsigned
	case signed
	case archives
	case downloads
	case inbox
	case caches
	case tmp
	case resume
	case certificates
	case log
}

private struct StorageEntry: Identifiable {
	let kind: StorageKind
	let title: String
	let systemImage: String
	let tint: Color
	let bytes: Int64
	let count: Int
	let countUnit: String
	let openURL: URL?
	let isClearable: Bool
	let clearMessage: String

	var id: String { kind.rawValue }
}

private struct StorageSnapshot {
	let apps: [StorageEntry]
	let packages: [StorageEntry]
	let caches: [StorageEntry]
	let others: [StorageEntry]

	let documentsBytes: Int64
	let libraryBytes: Int64
	let tempBytes: Int64
	let deviceFree: Int64?
	let deviceTotal: Int64?

	var appBytes: Int64 { documentsBytes + libraryBytes + tempBytes }

	var allEntries: [StorageEntry] { apps + packages + caches + others }

	func entry(for kind: StorageKind) -> StorageEntry? {
		allEntries.first(where: { $0.kind == kind })
	}
}

// MARK: - 统计

private enum StorageScanner {
	static func snapshot() -> StorageSnapshot {
		let fileManager = FileManager.default
		let documents = URL.documentsDirectory
		let library = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
		let applicationSupport = try? fileManager.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: false
		)

		let unsignedURL = fileManager.unsigned
		let signedURL = fileManager.signed
		let archivesURL = fileManager.archives
		let downloadsURL = documents.appendingPathComponent("Downloads")
		let inboxURL = SharedInbox.inbox
		let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
		let tempURL = fileManager.temporaryDirectory
		let resumeURL = applicationSupport?.appendingPathComponent("ResumeData")
		let certificatesURL = applicationSupport?.appendingPathComponent("Certificates")
		let logURL = documents.appendingPathComponent("ksign-diag.log")

		let logStats = fileStats(logURL)

		let apps: [StorageEntry] = [
			StorageEntry(
				kind: .unsigned,
				title: "已下载应用",
				systemImage: "tray.and.arrow.down.fill",
				tint: .blue,
				bytes: StorageFootprint.allocatedSize(of: unsignedURL),
				count: childCount(unsignedURL),
				countUnit: "个应用",
				openURL: unsignedURL,
				isClearable: true,
				clearMessage: "将删除所有「已下载应用」的解压文件，并清空资源库里的已下载条目。此操作不可撤销。"
			),
			StorageEntry(
				kind: .signed,
				title: "已签名应用",
				systemImage: "signature",
				tint: .green,
				bytes: StorageFootprint.allocatedSize(of: signedURL),
				count: childCount(signedURL),
				countUnit: "个应用",
				openURL: signedURL,
				isClearable: true,
				clearMessage: "将删除所有「已签名应用」的文件，并清空资源库里的已签名条目。此操作不可撤销。"
			)
		]

		let packages: [StorageEntry] = [
			StorageEntry(
				kind: .archives,
				title: "导出存档",
				systemImage: "archivebox.fill",
				tint: .orange,
				bytes: StorageFootprint.allocatedSize(of: archivesURL),
				count: childCount(archivesURL),
				countUnit: "个安装包",
				openURL: archivesURL,
				isClearable: true,
				clearMessage: "将删除每次安装/导出时生成的历史 ipa 包，不影响资源库和已安装的 App。"
			),
			StorageEntry(
				kind: .downloads,
				title: "下载的原包",
				systemImage: "square.and.arrow.down.fill",
				tint: .teal,
				bytes: StorageFootprint.allocatedSize(of: downloadsURL),
				count: childCount(downloadsURL),
				countUnit: "个安装包",
				openURL: downloadsURL,
				isClearable: true,
				clearMessage: "将删除所有下载的原始 ipa；正在进行的下载可能失败。"
			),
			StorageEntry(
				kind: .inbox,
				title: "分享收件箱",
				systemImage: "tray.full.fill",
				tint: .indigo,
				bytes: StorageFootprint.allocatedSize(of: inboxURL),
				count: childCount(inboxURL),
				countUnit: "个文件",
				openURL: nil,
				isClearable: true,
				clearMessage: "将删除分享扩展交接给主 App、但还没导入的文件。"
			)
		]

		let cacheEntries: [StorageEntry] = [
			StorageEntry(
				kind: .caches,
				title: "图片与网络缓存",
				systemImage: "photo.stack.fill",
				tint: .pink,
				bytes: StorageFootprint.allocatedSize(of: cachesURL),
				count: childCount(cachesURL),
				countUnit: "个文件",
				openURL: cachesURL,
				isClearable: true,
				clearMessage: "将清空图片和网络缓存，之后用到时会重新下载，不影响任何数据。"
			),
			StorageEntry(
				kind: .tmp,
				title: "工作缓存（tmp）",
				systemImage: "clock.arrow.circlepath",
				tint: .gray,
				bytes: StorageFootprint.allocatedSize(of: tempURL),
				count: childCount(tempURL),
				countUnit: "个文件",
				openURL: tempURL,
				isClearable: true,
				clearMessage: "将清空临时目录；正在进行的导入、签名或安装可能失败。"
			),
			StorageEntry(
				kind: .resume,
				title: "断点续传数据",
				systemImage: "arrow.down.circle",
				tint: .purple,
				bytes: StorageFootprint.allocatedSize(of: resumeURL),
				count: childCount(resumeURL),
				countUnit: "个断点",
				openURL: resumeURL,
				isClearable: true,
				clearMessage: "将删除下载中断时保存的续传数据；未完成的下载需要从头开始。"
			)
		]

		let others: [StorageEntry] = [
			StorageEntry(
				kind: .certificates,
				title: "证书与描述文件",
				systemImage: "person.text.rectangle.fill",
				tint: .brown,
				bytes: StorageFootprint.allocatedSize(of: certificatesURL),
				count: childCount(certificatesURL),
				countUnit: "个证书",
				openURL: nil,
				isClearable: false,
				clearMessage: "证书请到「设置 → 证书」里管理，这里只显示占用。"
			),
			StorageEntry(
				kind: .log,
				title: "诊断日志",
				systemImage: "doc.text.fill",
				tint: .secondary,
				bytes: logStats.bytes,
				count: logStats.files,
				countUnit: "个文件",
				openURL: nil,
				isClearable: true,
				clearMessage: "将删除 ksign-diag.log，下次启动会重新生成。"
			)
		]

		let volume = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
			forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
		)

		return StorageSnapshot(
			apps: apps,
			packages: packages,
			caches: cacheEntries,
			others: others,
			documentsBytes: StorageFootprint.allocatedSize(of: documents),
			libraryBytes: StorageFootprint.allocatedSize(of: library),
			tempBytes: StorageFootprint.allocatedSize(of: tempURL),
			deviceFree: volume?.volumeAvailableCapacityForImportantUsage,
			deviceTotal: volume?.volumeTotalCapacity.map(Int64.init)
		)
	}

	private static func childCount(_ url: URL?) -> Int {
		guard let url else { return 0 }
		return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).count) ?? 0
	}

	private static func fileStats(_ url: URL) -> (bytes: Int64, files: Int) {
		guard
			let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
			let size = attributes[.size] as? NSNumber
		else {
			return (0, 0)
		}
		return (size.int64Value, 1)
	}
}

// MARK: - 清理请求

private enum ClearRequest: Identifiable {
	enum Batch: String, CaseIterable {
		case cachesAndTemp
		case packages
		case apps
		case everything
	}

	case entry(StorageEntry)
	case batch(Batch)

	var id: String {
		switch self {
		case .entry(let entry): return "entry-\(entry.id)"
		case .batch(let batch): return "batch-\(batch.rawValue)"
		}
	}

	var title: String {
		switch self {
		case .entry(let entry):
			return "清理「\(entry.title)」？"
		case .batch(.cachesAndTemp):
			return "清理缓存与临时文件？"
		case .batch(.packages):
			return "清理安装包与导出？"
		case .batch(.apps):
			return "清理全部应用数据？"
		case .batch(.everything):
			return "全部清理（保留应用与证书）？"
		}
	}

	var message: String {
		switch self {
		case .entry(let entry):
			return entry.clearMessage
		case .batch(.cachesAndTemp):
			return "将清空图片/网络缓存、工作缓存（tmp）、断点续传和诊断日志。正在进行的导入、签名或安装可能失败。"
		case .batch(.packages):
			return "将删除导出存档、下载的原包和分享收件箱里的文件，不影响资源库和已安装的 App。"
		case .batch(.apps):
			return "将删除全部已下载应用和已签名应用（含资源库条目）。此操作不可撤销。"
		case .batch(.everything):
			return "将清理缓存、临时文件、断点续传、诊断日志、导出存档、下载原包和分享收件箱；应用与证书保留。"
		}
	}

	var batchKinds: [StorageKind] {
		switch self {
		case .entry(let entry):
			return [entry.kind]
		case .batch(.cachesAndTemp):
			return [.caches, .tmp, .resume, .log]
		case .batch(.packages):
			return [.archives, .downloads, .inbox]
		case .batch(.apps):
			return [.unsigned, .signed]
		case .batch(.everything):
			return [.archives, .downloads, .inbox, .caches, .tmp, .resume, .log]
		}
	}
}

// MARK: - 视图

struct StorageView: View {
	@AppStorage("Feather.storageLimitGB") private var _storageLimitGB: Int = 0

	@State private var snapshot: StorageSnapshot?
	@State private var isScanning = false
	@State private var clearRequest: ClearRequest?
	@State private var lastFreed: Int64 = 0

	var body: some View {
		NBList("存储与清理") {
			_overview()

			if let snapshot {
				_section("应用数据", secondary: formatted(snapshot.apps.reduce(0) { $0 + $1.bytes }), entries: snapshot.apps)
				_section("安装包与导出", secondary: formatted(snapshot.packages.reduce(0) { $0 + $1.bytes }), entries: snapshot.packages)
				_section("缓存与临时文件", secondary: formatted(snapshot.caches.reduce(0) { $0 + $1.bytes }), entries: snapshot.caches)
				_section("其他", secondary: formatted(snapshot.others.reduce(0) { $0 + $1.bytes }), entries: snapshot.others)
			}

			_autoClean()
			_actions()

			Section {
				Text("iOS 设置里 Ksign 的「文稿与数据」= 文档 + 缓存与支持文件 + 临时文件，是这三部分的总和；资源库删除只覆盖「已下载应用」和「已签名应用」两份副本。")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					refresh()
				} label: {
					if isScanning {
						ProgressView()
					} else {
						Image(systemName: "arrow.clockwise")
					}
				}
				.disabled(isScanning)
			}
		}
		.overlay {
			if snapshot == nil {
				ProgressView("正在计算占用…")
					.padding(20)
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
		}
		.task { refresh() }
		.alert(item: $clearRequest) { request in
			Alert(
				title: Text(request.title),
				message: Text(request.message),
				primaryButton: .destructive(Text("清理")) {
					perform(request)
				},
				secondaryButton: .cancel(Text("取消"))
			)
		}
	}
}

// MARK: - 视图：分区

private extension StorageView {
	@ViewBuilder
	func _overview() -> some View {
		Section {
			VStack(alignment: .leading, spacing: 12) {
				HStack(alignment: .top) {
					VStack(alignment: .leading, spacing: 3) {
						Text("Ksign 占用")
							.font(.caption)
							.foregroundStyle(.secondary)
						Text(formatted(snapshot?.appBytes ?? 0))
							.font(.system(size: 30, weight: .bold, design: .rounded))
							.monospacedDigit()
							.contentTransition(.numericText())
					}

					Spacer()

					VStack(alignment: .trailing, spacing: 3) {
						Text("设备可用")
							.font(.caption)
							.foregroundStyle(.secondary)
						Text(formatted(snapshot?.deviceFree ?? 0))
							.font(.callout.weight(.medium))
							.monospacedDigit()
					}
				}

				if let total = snapshot?.deviceTotal, total > 0 {
					let free = snapshot?.deviceFree ?? 0
					let used = max(0, total - free)
					ProgressView(value: Double(used), total: Double(total))
						.tint(.accentColor)
					Text("设备总容量 \(formatted(total)) · 已用 \(formatted(used))")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}

				if let snapshot {
					Text("文档 \(formatted(snapshot.documentsBytes)) · 缓存与支持文件 \(formatted(snapshot.libraryBytes)) · 临时 \(formatted(snapshot.tempBytes))")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
			.padding(.vertical, 2)
		}
	}

	@ViewBuilder
	func _section(_ title: String, secondary: String, entries: [StorageEntry]) -> some View {
		NBSection(title, secondary: secondary) {
			ForEach(entries) { entry in
				_row(entry)
			}
		}
	}

	@ViewBuilder
	func _row(_ entry: StorageEntry) -> some View {
		HStack(spacing: 12) {
			Image(systemName: entry.systemImage)
				.font(.system(size: 15, weight: .semibold))
				.foregroundStyle(.white)
				.frame(width: 32, height: 32)
				.background(entry.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

			VStack(alignment: .leading, spacing: 2) {
				Text(entry.title)
					.font(.body)
				Text(entry.count == 0 ? "空" : "\(entry.count) \(entry.countUnit)")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Spacer(minLength: 8)

			VStack(alignment: .trailing, spacing: 4) {
				Text(formatted(entry.bytes))
					.font(.subheadline.weight(.semibold))
					.monospacedDigit()
					.foregroundStyle(entry.bytes > 0 ? Color.primary : Color.secondary)

				if entry.isClearable {
					Button("清理") {
						clearRequest = .entry(entry)
					}
					.font(.caption2)
					.buttonStyle(.borderless)
					.foregroundStyle(.red)
					.disabled(entry.bytes == 0)
				} else {
					Image(systemName: "lock")
						.font(.caption2)
						.foregroundStyle(Color.secondary)
				}
			}
		}
		.contextMenu {
			if let url = entry.openURL, let shared = url.toSharedDocumentsURL() {
				Button("在「文件」中打开", systemImage: "folder") {
					UIApplication.open(shared)
				}
			}
		}
	}

	@ViewBuilder
	func _autoClean() -> some View {
		NBSection("自动清理") {
			Picker("存储上限", selection: $_storageLimitGB) {
				Text("关闭").tag(0)
				Text("1 GB").tag(1)
				Text("2 GB").tag(2)
				Text("3 GB").tag(3)
				Text("5 GB").tag(5)
				Text("10 GB").tag(10)
				Text("20 GB").tag(20)
			}

			Button {
				runJanitor()
			} label: {
				Label("立即检查并清理", systemImage: "wand.and.stars")
			}
			.disabled(_storageLimitGB == 0 || isScanning)
		} footer: {
			Text("超过上限时按顺序自动清理：导出存档（最旧优先）→ 缓存与临时文件 → 下载原包（最旧优先）→ 已签名应用（最旧优先）。不会删除已下载应用和证书。App 启动、导入或签名完成后会自动检查。")
		}
	}

	@ViewBuilder
	func _actions() -> some View {
		NBSection("高级清理") {
			Button {
				clearRequest = .batch(.cachesAndTemp)
			} label: {
				Label("清理缓存与临时文件", systemImage: "wind")
			}

			Button {
				clearRequest = .batch(.packages)
			} label: {
				Label("清理安装包与导出", systemImage: "shippingbox")
			}

			Button {
				clearRequest = .batch(.everything)
			} label: {
				Label("全部清理（保留应用与证书）", systemImage: "trash")
			}

			Button(role: .destructive) {
				clearRequest = .batch(.apps)
			} label: {
				Label("清理全部应用数据", systemImage: "trash.fill")
			}
		} footer: {
			if lastFreed > 0 {
				Text("上次清理释放约 \(formatted(lastFreed))。正在进行的导入、签名或安装期间请勿清理。")
			} else {
				Text("清理只删除对应目录里的文件，不改动设置和证书。正在进行的导入、签名或安装期间请勿清理。")
			}
		}
	}
}

// MARK: - 视图：动作

private extension StorageView {
	func refresh() {
		guard !isScanning else { return }
		isScanning = true
		Task { @MainActor in
			let result = await Task.detached(priority: .userInitiated) {
				StorageScanner.snapshot()
			}.value
			snapshot = result
			isScanning = false
		}
	}

	func runJanitor() {
		guard _storageLimitGB > 0, !isScanning else { return }
		isScanning = true
		StorageJanitor.enforceIfNeeded { freed in
			lastFreed = freed
			isScanning = false
			refresh()
		}
	}

	func perform(_ request: ClearRequest) {
		let kinds = request.batchKinds
		let freed = kinds.reduce(Int64(0)) { partial, kind in
			partial + (snapshot?.entry(for: kind)?.bytes ?? 0)
		}

		let fileManager = FileManager.default
		let documents = URL.documentsDirectory
		let applicationSupport = try? fileManager.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: false
		)

		for kind in kinds {
			switch kind {
			case .unsigned:
				ResetView.deleteImportedApps()
			case .signed:
				ResetView.deleteSignedApps()
			case .archives:
				removeContents(of: fileManager.archives)
			case .downloads:
				removeContents(of: documents.appendingPathComponent("Downloads"))
				NotificationCenter.default.post(name: .ksignStorageCleared, object: nil)
			case .inbox:
				removeContents(of: SharedInbox.inbox)
			case .caches:
				ResetView.clearNetworkCache()
			case .tmp:
				ResetView.clearWorkCache()
			case .resume:
				removeContents(of: applicationSupport?.appendingPathComponent("ResumeData"))
			case .certificates:
				break
			case .log:
				try? fileManager.removeItem(at: documents.appendingPathComponent("ksign-diag.log"))
			}
		}

		// ResetView 删的是整个目录，导入/签名依赖这些目录存在，清完立即补回来。
		recreateAppDirectories()

		DiagLog.log("storage: cleared \(kinds.map(\.rawValue).joined(separator: ",")), freed≈\(freed)")
		lastFreed = freed
		refresh()
	}

	func recreateAppDirectories() {
		let fileManager = FileManager.default
		let appDirectory = URL.documentsDirectory.appendingPathComponent("App")
		try? fileManager.createDirectoryIfNeeded(at: appDirectory)
		for name in ["Signed", "Unsigned", "Archives", "Server", "Tweaks"] {
			try? fileManager.createDirectoryIfNeeded(at: appDirectory.appendingPathComponent(name))
		}
	}

	func removeContents(of url: URL?) {
		guard let url else { return }
		let fileManager = FileManager.default
		guard let items = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
			return
		}
		for item in items {
			try? fileManager.removeItem(at: item)
		}
	}

	func formatted(_ bytes: Int64) -> String {
		guard bytes > 0 else { return "0 KB" }
		return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
	}
}
