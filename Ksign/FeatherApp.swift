//
//  FeatherApp.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import Combine
import Nuke
import OSLog
import IDeviceSwift

@main
struct FeatherApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

	var body: some Scene {
		WindowGroup {
			RootView()
		}
	}
}

/// 根视图：从 FeatherApp.body 抽出来。
/// 这样做是为了让自定义 SceneDelegate 也能用 UIHostingController 挂载同一棵树
/// （全能签就是 UIKit + SceneDelegate 的结构，URL 由 scene 回调直接接管）。
struct RootView: View {
	let heartbeat = HeartbeatManager.shared
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject var accentColorManager = AccentColorManager.shared
	@StateObject var extractManager = ExtractManager.shared
	@StateObject var logsManager = LogsManager.shared
	let storage = Storage.shared

	@State private var inboxTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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
		.onOpenURL(perform: _handleURL)
		.animation(.smooth, value: downloadManager.manualDownloads.description)
		.animation(.smooth, value: extractManager.extractItems.description)
		.onReceive(accentColorManager.objectWillChange) { _ in
			accentColorManager.updateGlobalTintColor()
		}
		// 不依赖 SwiftUI 的 scenePhase：自定义 SceneDelegate 挂载时
		// scenePhase 环境值不一定驱动，直接听 UIKit 的激活通知更稳。
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
			DiagLog.write("didBecomeActive -> rescan")
			URLRouter.importInboxFiles()
			URLRouter.sweepDocuments(reason: "active")
			SharedInbox.mergeExtensionDiagnostics()
			URLRouter.importSharedInbox()
		}
		.onReceive(inboxTimer) { _ in
			URLRouter.importInboxFiles()
			URLRouter.importSharedInbox()
		}
		.onAppear {
			accentColorManager.updateGlobalTintColor()
			if logsManager.isCapturing { logsManager.startCapture() }
		}
	}

	private func _handleURL(_ url: URL) {
		DiagLog.write("onOpenURL \(url.absoluteString)")
		print("[RootView] onOpenURL fired")
		URLRouter.shared.handle(url)
	}
}

/// 和全能签同构：场景由自己的 SceneDelegate 建立，
/// URL 从 scene:willConnectToSession:options: 与 scene:openURLContexts: 直接拿到，
/// 不再依赖 SwiftUI 内部 scene delegate 是否把事件转给 .onOpenURL。
@objc(KsignSceneDelegate)
final class KsignSceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?

	func scene(
		_ scene: UIScene,
		willConnectTo session: UISceneSession,
		options connectionOptions: UIScene.ConnectionOptions
	) {
		DiagLog.write("SceneDelegate willConnect urls=\(connectionOptions.urlContexts.count)")

		guard let windowScene = scene as? UIWindowScene else { return }
		let window = UIWindow(windowScene: windowScene)
		window.rootViewController = UIHostingController(rootView: RootView())
		self.window = window
		window.makeKeyAndVisible()

		for context in connectionOptions.urlContexts {
			DiagLog.write("SceneDelegate cold-start url \(context.url.absoluteString)")
			URLRouter.shared.handle(context.url)
		}
	}

	func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
		DiagLog.write("SceneDelegate openURLContexts=\(URLContexts.count)")
		for context in URLContexts {
			URLRouter.shared.handle(context.url)
		}
	}
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        DiagLog.resetIfNeeded()
        DiagLog.write("didFinishLaunching keys=\(launchOptions?.keys.map { $0.rawValue }.joined(separator: ",") ?? "nil")")

        // Inbox 兜底多扫几次：系统复制文件的时机可能晚于 didFinishLaunching
        for delay in [0.0, 0.4, 1.0, 2.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
                let list = (try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []
                DiagLog.write("inbox scan(+\(delay)): \(list.count) item(s) \(list)")
                URLRouter.importInboxFiles()
                SharedInbox.mergeExtensionDiagnostics()
                URLRouter.importSharedInbox()
            }
        }

        // 场景健康检查：确认 SwiftUI 的 window 正常建立（黑屏/场景异常时能看出来）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.map { $0.windows.count }
            DiagLog.write("scene check: scenes=\(scenes.count) windows=\(windows)")
        }

        // Documents 根目录兜底：用户把 IPA 直接放进「文件 App → 我的 iPhone → Ksign」也能导入
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            URLRouter.sweepDocuments(reason: "launch")
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
        DiagLog.write("application(_:open:) \(url.absoluteString)")
        print("[AppDelegate] application(open:) fired")
        URLRouter.shared.handle(url)
        return true
    }



    // 注意：这里不要实现 application(_:configurationForConnecting:options:)。
    // SwiftUI 的 App 生命周期需要自己提供带内部 scene delegate 的 UISceneConfiguration；
    // 我们一旦覆写并返回 name:nil 的配置，场景就没有 delegate，
    // scene:openURLContexts: 无人接收 —— 表现为「用其他应用打开」时 App 起来了但文件没进来。
    // URL 由 SwiftUI 的 .onOpenURL 统一处理（含冷启动）。

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
