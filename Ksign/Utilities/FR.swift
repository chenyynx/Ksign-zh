//
//  FR.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import Foundation.NSURL
import UIKit.UIImage
import Zsign
import NimbleJSON
import AltSourceKit
import IDeviceSwift

enum FR {
	/// 导入 IPA。`progress` 按阶段回报 0…1（复制 0.25 / 解压 0.75 / 移动 0.9 / 入库 1.0），
	/// 供上层复用 ExtractManager 的进度横幅。
	static func handlePackageFile(
		_ ipa: URL,
		download: Download? = nil,
		progress: ((Double) -> Void)? = nil,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = AppFileHandler(file: ipa, download: download)

			func report(_ value: Double) async {
				guard let progress else { return }
				await MainActor.run { progress(value) }
			}

			do {
				try await handler.copy()
				await report(0.25)
				try await handler.extract()
				await report(0.75)
				try await handler.move()
				await report(0.9)
				try await handler.addToDatabase()

                                try? await handler.clean()
				await report(1.0)
				await MainActor.run {
					completion(nil)
				}
			} catch {
				try await handler.clean()
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	static func signPackageFile(
		_ app: AppInfoPresentable,
		using options: Options,
		icon: UIImage?,
		certificate: CertificatePair?,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = SigningHandler(app: app, options: options)
			if !options.onlyModify {
				handler.appCertificate = certificate
			}
			handler.appIcon = icon
			
			do {
				try await handler.copy()
				try await handler.modify()
                try? await handler.clean()
				
				await MainActor.run {
					completion(nil)
				}
			} catch {
				try? await handler.clean()
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	static func handleCertificateFiles(
		p12URL: URL,
		provisionURL: URL,
		p12Password: String,
		certificateName: String,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = CertificateFileHandler(
				key: p12URL,
				provision: provisionURL,
				password: p12Password,
				nickname: certificateName.isEmpty ? nil : certificateName
			)
			
			do {
				try await handler.copy()
				try await handler.addToDatabase()
				await MainActor.run {
					completion(nil)
				}
			} catch {
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	
	static func checkPasswordForCertificate(
		for key: URL,
		with password: String,
		using provision: URL
	) -> Bool {
		defer {
			password_check_fix_WHAT_THE_FUCK_free(provision.path)
		}
		
		password_check_fix_WHAT_THE_FUCK(provision.path)
		
		if (!p12_password_check(key.path, password)) {
			return false
		}
		
		return true
	}
	
	static func checkPasswordForCertificateData(
		p12Data: Data,
		provisionData: Data,
		password: String
	) -> Bool {
		let tempDir = FileManager.default.temporaryDirectory
		let tempP12 = tempDir.appendingPathComponent("temp_cert.p12")
		let tempProvision = tempDir.appendingPathComponent("temp_provision.mobileprovision")
		
		defer {
			try? FileManager.default.removeItem(at: tempP12)
			try? FileManager.default.removeItem(at: tempProvision)
		}
		
		do {
			try p12Data.write(to: tempP12)
			try provisionData.write(to: tempProvision)
			
			return checkPasswordForCertificate(for: tempP12, with: password, using: tempProvision)
		} catch {
			print("Error creating temporary files for password check: \(error)")
			return false
		}
	}
	
	static func movePairing(_ url: URL) {
		let fileManager = FileManager.default
		let dest = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")

		try? fileManager.removeFileIfNeeded(at: dest)
		
		try? fileManager.copyItem(at: url, to: dest)
		
		HeartbeatManager.shared.start(true)
	}
	
	#if SERVER
	static func downloadSSLCertificates(
		from urlString: String,
		completion: @escaping (Bool) -> Void
	) {
		let generator = UINotificationFeedbackGenerator()
		generator.prepare()
		
		NBFetchService().fetch(from: urlString) { (result: Result<ServerPackModel, Error>) in
			switch result {
			case .success(let pack):
				do {
					let serverDir = URL.documentsDirectory.appendingPathComponent("App").appendingPathComponent("Server")
					let pemURL = serverDir.appendingPathComponent("server.pem")
					let crtURL = serverDir.appendingPathComponent("server.crt")
					let commonNameURL = serverDir.appendingPathComponent("commonName.txt")
					
					try FileManager.default.createDirectoryIfNeeded(at: serverDir)
					try pack.key.write(to: pemURL, atomically: true, encoding: .utf8)
					try pack.cert.write(to: crtURL, atomically: true, encoding: .utf8)
					try pack.info.domains.commonName.write(to: commonNameURL, atomically: true, encoding: .utf8)
					
					generator.notificationOccurred(.success)
					completion(true)
				} catch {
					completion(false)
				}
			case .failure(_):
				completion(false)
			}
		}
	}
	#endif
	
	/// 拉取并写入一个软件源。
	/// - Parameters:
	///   - isBuiltIn: 标记为内置源（写入 Core Data 的 isBuiltIn 字段）。
	///   - silent: 不弹错误框。内置源在启动时静默拉取，失败由调用方安排下次重试，
	///     避免离线启动连续弹 5 个错误框。
	///   - completion: 目标状态是否达成。源已存在也算成功（取消/去重不丢重试机会）。
	static func handleSource(
		_ urlString: String,
		isBuiltIn: Bool = false,
		silent: Bool = false,
		completion: @escaping (Bool) -> Void
	) {
		guard let url = URL(string: urlString) else { completion(false); return }

		NBFetchService().fetch<ASRepository>(from: url) { (result: Result<ASRepository, Error>) in
			switch result {
			case .success(let data):
				let id = data.id ?? url.absoluteString

				if !Storage.shared.sourceExists(id) {
					Storage.shared.addSource(url, repository: data, id: id, isBuiltIn: isBuiltIn) { error in
						completion(error == nil)
					}
				} else {
					if !silent {
						DispatchQueue.main.async {
							UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("Repository already added."))
						}
					}
					completion(true)
				}
			case .failure(let error):
				if !silent {
					DispatchQueue.main.async {
						UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
					}
				}
				completion(false)
			}
		}
	}
}

private enum CertificateHandlerError: Error {
	case invalidCertificate
}
