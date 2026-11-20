//
//  Server.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import Vapor
import NIOSSL
import NIOTLS
import SwiftUI
import IDeviceSwift

// MARK: - Class
class ServerInstaller: Identifiable, ObservableObject {
	let id = UUID()
	let port = Int.random(in: 4000...8000)
	private var _needsShutdown = false
	
	var packageUrl: URL?
	var app: AppInfoPresentable
	@ObservedObject var viewModel: InstallerStatusViewModel
	private let _server: Application

	init(app: AppInfoPresentable, viewModel: InstallerStatusViewModel) throws {
		self.app = app
		self.viewModel = viewModel
		self._server = try Self.setupApp(port: port)
		
		try _configureRoutes()
		try _server.server.start()
		_needsShutdown = true
	}
	
	deinit {
		_shutdownServer()
	}
		
	private func _configureRoutes() throws {
		_server.get("*") { [weak self] req in
			guard let self else { return Response(status: .badGateway) }
			switch req.url.path {
			case plistEndpoint.path:
				self._updateStatus(.sendingManifest)
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "text/xml",
				], body: .init(data: installManifestData))
			case displayImageSmallEndpoint.path:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageSmallData))
			case displayImageLargeEndpoint.path:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageLargeData))
			case payloadEndpoint.path:
				guard let packageUrl = packageUrl else {
					return Response(status: .notFound)
				}
				
				self._updateStatus(.sendingPayload)
				
				return req.fileio.streamFile(
					at: packageUrl.path
				) { result in
                    switch result {
                    case .success:
                        self._updateStatus(.installing)
                    case .failure(let error):
                        self._updateStatus(.broken(error))
                    }
				}
			case "/install":
				var headers = HTTPHeaders()
				headers.add(name: .contentType, value: "text/html")
				return Response(status: .ok, headers: headers, body: .init(string: self.html))
			default:
				return Response(status: .notFound)
			}
		}
	}
	
	private func _shutdownServer() {
		guard _needsShutdown else { return }
		
		_needsShutdown = false
		_server.server.shutdown()
		_server.shutdown()
	}
	
    private func _updateStatus(_ newStatus: InstallerStatusViewModel.InstallerStatus) {
		DispatchQueue.main.async {
			self.viewModel.status = newStatus
		}
	}
		
	static func getServerMethod() -> Int {
		// 界面上这个值是 @AppStorage，默认 1（半本地）；这里直接读 UserDefaults，
		// key 不存在时 integer(forKey:) 返回 0（完全本地）——两处默认值不一致，
		// 表现就是「设置里明明选着半本地，实际按完全本地起 https + *.backloop.dev」，
		// 安装页永远证书错误。key 缺失时按界面的默认值 1 处理。
		if UserDefaults.standard.object(forKey: "Feather.serverMethod") == nil {
			return 1
		}
		return UserDefaults.standard.integer(forKey: "Feather.serverMethod")
	}
	
	static func getIPFix() -> Bool {
		UserDefaults.standard.bool(forKey: "Feather.ipFix")
	}
	
	static func setServerMethod(_ method: Int) {
		UserDefaults.standard.set(method, forKey: "Feather.serverMethod")
	}
	
	static func setIPFix(_ enabled: Bool) {
		UserDefaults.standard.set(enabled, forKey: "Feather.ipFix")
	}
}
