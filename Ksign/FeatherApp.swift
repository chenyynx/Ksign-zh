//
//  FeatherApp.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import Nuke
import OSLog
import IDeviceSwift
import UIKit

// MARK: - Root view
/// 原 SwiftUI App 的根视图。改用 UIKit 生命周期后由 SceneDelegate 用
/// UIHostingController 承载，盖在 UIDocumentBrowserViewController 上。
struct RootView: View {
	let heartbeat = HeartbeatManager.shared
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject var accentColorManager = AccentColorManager.shared
	@StateObject var extractManager = ExtractManager.shared
	@StateObject var logsManager = LogsManager.shared
	let storage = Storage.shared

	var body: some View {
		VStack {
			ExtractHeaderView(extractManager: extractManager)
				.transition(.move(edge: .top).combined(with: .opacity))
			DownloadHeaderView(downloadManager: downloadManager)
				.transition(.move(edge: .top).combined(with: .opacity))
			VariedTabbarView()
				.environment(\.managedObjectContext, storage.context)
				.transition(.move(edge: .top).combined(with: .opacity))
		}
		.animation(.smooth, value: downloadManager.manualDownloads.description)
		.animation(.smooth, value: extractManager.extractItems.description)
		.onReceive(accentColorManager.objectWillChange) { _ in
			accentColorManager.updateGlobalTintColor()
		}
		.onAppear {
			accentColorManager.updateGlobalTintColor()
			if logsManager.isCapturing { logsManager.startCapture() }
		}
	}
}

// MARK: - App delegate
@main
class AppDelegate: NSObject, UIApplicationDelegate {
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {

		DiagLog.logLaunchInfo()

		_createPipeline()
		_createSourcesDirectory()
		// v2：首次安装、老版本升级、或源列表被清空时补写内置源
		// （handleSource 会按 identifier 去重，不会重复添加）。
		// 「已初始化」只在成功写入至少一个源后置位，见 _initializeBuiltInSources。
		if !UserDefaults.standard.bool(forKey: "hasInitializedBuiltInSources.v2")
			|| Storage.shared.getSources().isEmpty {
			_initializeBuiltInSources()
		}

		_clean()

		_copyServerCertificates()
		_addDefaultCertificates()

#if SERVER
		// fallback just in case xd
		_downloadSSLCertificates()
#endif
		return true
	}

	/// 场景由 SceneDelegate 接管：window 根控制器是 UIDocumentBrowserViewController，
	/// 主界面以覆盖层形式呈现。plist 里也声明了同一配置，两处保持一致。
	func application(
		_ application: UIApplication,
		configurationForConnecting connectingSceneSession: UISceneSession,
		options: UIScene.ConnectionOptions
	) -> UISceneConfiguration {
		let configuration = UISceneConfiguration(
			name: "Default Configuration",
			sessionRole: connectingSceneSession.role
		)
		configuration.delegateClass = SceneDelegate.self
		return configuration
	}

	/// 极少数不经过 scene 的唤起路径也统一转给同一个入口。
	func application(
		_ app: UIApplication,
		open url: URL,
		options: [UIApplication.OpenURLOptionsKey: Any]
	) -> Bool {
		SceneDelegate.handle(url, source: "appDelegate")
		return true
	}

	private func _initializeBuiltInSources() {
		Storage.shared.addBuiltInSources { successCount in
			// 全部失败（离线首启）不置标记，下次启动继续重试；
			// 列表为空也会在下次启动再次进入本流程。
			if successCount > 0 {
				UserDefaults.standard.set(true, forKey: "hasInitializedBuiltInSources.v2")
			}
		}
	}

	private func _createPipeline() {
		DataLoader.sharedUrlCache.diskCapacity = 0

		let pipeline = ImagePipeline {
			let dataLoader: DataLoader = {
				let config = URLSessionConfiguration.default
				config.urlCache = nil
				return DataLoader(configuration: config)
			}()
			let dataCache = try? DataCache(name: "thewonderofyou.Feather.datacache") // disk cache
			let imageCache = Nuke.ImageCache() // memory cache
			dataCache?.sizeLimit = 500 * 1024 * 1024
			imageCache.costLimit = 100 * 1024 * 1024
			$0.dataCache = dataCache
			$0.imageCache = imageCache
			$0.dataLoader = dataLoader
			$0.dataCachePolicy = .automatic
			$0.isStoringPreviewsInMemoryCache = false
		}

		ImagePipeline.shared = pipeline
	}

	private func _createSourcesDirectory() {
		let fileManager = FileManager.default

		let appDirectory = URL.documentsDirectory.appendingPathComponent("App")
		try? fileManager.createDirectoryIfNeeded(at: appDirectory)

		let directories = ["Signed", "Unsigned", "Archives", "Server", "Tweaks"].map {
			appDirectory.appendingPathComponent($0)
		}

		for url in directories {
			try? fileManager.createDirectoryIfNeeded(at: url)
		}
	}

	private func _clean() {
		let fileManager = FileManager.default
		let tmpDirectory = fileManager.temporaryDirectory

		if let files = try? fileManager.contentsOfDirectory(atPath: tmpDirectory.path()) {
			for file in files {
				try? fileManager.removeItem(atPath: tmpDirectory.appendingPathComponent(file).path())
			}
		}
	}

	private func _copyServerCertificates() {
		let fileManager = FileManager.default
		let serverDirectory = URL.documentsDirectory.appendingPathComponent("App/Server")

		try? fileManager.createDirectoryIfNeeded(at: serverDirectory)

		let filesToCopy = ["server.crt", "server.pem", "commonName.txt"]

		for fileName in filesToCopy {
			guard let bundleURL = Bundle.main.url(forResource: fileName.components(separatedBy: ".").first!, withExtension: fileName.components(separatedBy: ".").last!) else {
				print("File \(fileName) not found in app bundle")
				continue
			}

			let destinationURL = serverDirectory.appendingPathComponent(fileName)

			try? fileManager.removeItem(at: destinationURL)

			do {
				try fileManager.copyItem(at: bundleURL, to: destinationURL)
			} catch {
				print("Error copying \(fileName): \(error)")
			}
		}
	}

	private func _addDefaultCertificates() {
		guard
			UserDefaults.standard.bool(forKey: "feather.didImportDefaultCertificates") == false,
			let signingAssetsURL = Bundle.main.url(forResource: "signing-assets", withExtension: nil)
		else {
			return
		}

		do {
			let folderContents = try FileManager.default.contentsOfDirectory(
				at: signingAssetsURL,
				includingPropertiesForKeys: nil,
				options: .skipsHiddenFiles
			)

			for folderURL in folderContents {
				guard folderURL.hasDirectoryPath else { continue }

				let certName = folderURL.lastPathComponent

				let p12Url = folderURL.appendingPathComponent("cert.p12")
				let provisionUrl = folderURL.appendingPathComponent("cert.mobileprovision")
				let passwordUrl = folderURL.appendingPathComponent("cert.txt")

				guard
					FileManager.default.fileExists(atPath: p12Url.path),
					FileManager.default.fileExists(atPath: provisionUrl.path),
					FileManager.default.fileExists(atPath: passwordUrl.path)
				else {
					Logger.misc.warning("Skipping \(certName): missing required files")
					continue
				}

				let password = try String(contentsOf: passwordUrl, encoding: .utf8)

				FR.handleCertificateFiles(
					p12URL: p12Url,
					provisionURL: provisionUrl,
					p12Password: password,
					certificateName: certName,
				) { _ in

				}
			}
			UserDefaults.standard.set(true, forKey: "feather.didImportDefaultCertificates")
		} catch {
			Logger.misc.error("Failed to list signing-assets: \(error)")
		}
	}

#if SERVER
	private func _downloadSSLCertificates() {
		let serverURL = "https://backloop.dev/pack.json"

		FR.downloadSSLCertificates(from: serverURL) { success in
			if success {
				print("SSL certificates downloaded successfully")
			} else {
				print("Failed to download SSL certificates")
			}
		}
	}
#endif
}
