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

@main
struct FeatherApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	@Environment(\.scenePhase) private var scenePhase
	let heartbeat = HeartbeatManager.shared
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject var accentColorManager = AccentColorManager.shared
    @StateObject var extractManager = ExtractManager.shared
	@StateObject var logsManager = LogsManager.shared
	let storage = Storage.shared

	var body: some Scene {
		WindowGroup {
			VStack {
                ExtractHeaderView(extractManager: extractManager)
                    .transition(.move(edge: .top).combined(with: .opacity))
				DownloadHeaderView(downloadManager: downloadManager)
					.transition(.move(edge: .top).combined(with: .opacity))
				VariedTabbarView()
					.environment(\.managedObjectContext, storage.context)
					.transition(.move(edge: .top).combined(with: .opacity))
			}
			.onOpenURL(perform: _handleURL)
			.animation(.smooth, value: downloadManager.manualDownloads.description)
            .animation(.smooth, value: extractManager.extractItems.description)
			.onReceive(accentColorManager.objectWillChange) { _ in
				accentColorManager.updateGlobalTintColor()
			}
			.onChange(of: scenePhase) { phase in
				if phase == .active {
					URLRouter.importInboxFiles()
				}
			}
			.onAppear {
				accentColorManager.updateGlobalTintColor()
				if logsManager.isCapturing { logsManager.startCapture() }
			}
		}
	}
	
	private func _handleURL(_ url: URL) {
		print("[FeatherApp] onOpenURL fired")
		URLRouter.shared.handle(url)
	}
	
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            URLRouter.importInboxFiles()
        }

        // 冷启动时系统通过 launchOptions 投递 URL（此时 SwiftUI 视图还没挂载，
        // .onOpenURL 收不到，必须在这里接）
        if let url = launchOptions?[.url] as? URL {
            URLRouter.shared.handle(url)
        }

        _createPipeline()
        _createSourcesDirectory()
        // v2：老版本升级后也补写一次内置源（handleSource 会按 identifier 去重，不会重复添加）
        if !UserDefaults.standard.bool(forKey: "hasInitializedBuiltInSources.v2") {
            _initializeBuiltInSources()
            UserDefaults.standard.set(true, forKey: "hasInitializedBuiltInSources.v2")
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
    
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        print("[AppDelegate] application(open:) fired")
        URLRouter.shared.handle(url)
        return true
    }


    /// 多场景保持开启：URL 可能随“新场景连接”一起到达，
    /// 这里先接住再延迟投递。返回配置用 name: nil，沿用 Info.plist 默认配置，
    /// 不改变场景能力，也不影响 SwiftUI 自己的 delegate。
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let url = options.urlContexts.first?.url {
            print("[AppDelegate] scene connecting with url: \(url.absoluteString)")
            UserDefaults.standard.set(url.absoluteString, forKey: "diag.lastURL")
            PendingURLStore.shared.url = url
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    private func _initializeBuiltInSources() { 
        Storage.shared.addBuiltInSources()
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


/// 暂存场景连接阶段收到的 URL，等界面就绪后再处理
final class PendingURLStore {
	static let shared = PendingURLStore()
	private init() {}

	var url: URL? {
		didSet { flushIfNeeded() }
	}

	private func flushIfNeeded() {
		guard url != nil else { return }
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
			guard let pending = self?.url else { return }
			self?.url = nil
			print("[PendingURLStore] flushing \(pending.absoluteString)")
			URLRouter.shared.handle(pending)
		}
	}
}
