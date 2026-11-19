//
//  ServerView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import Foundation
import SwiftUI
import NimbleJSON
import NimbleViews

// MARK: - Manifest server test state
private enum ManifestServerTestState: Equatable {
	case idle
	case testing
	case reachable(milliseconds: Int)
	case failed(message: String)
}

struct ServerView: View {
	@AppStorage("Feather.ipFix") private var _ipFix: Bool = false
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 1

	// P1：OTA 清单服务（默认自建；官方 palera.in 已停服；可自定义）
	@AppStorage(ManifestServer.Keys.source) private var _manifestSource: Int = ManifestServer.Source.builtIn.rawValue
	@AppStorage(ManifestServer.Keys.customBase) private var _manifestBase: String = ""
	@State private var _manifestTest: ManifestServerTestState = .idle

	private let _serverMethods: [String] = [
		.localized("Fully Local"),
		.localized("Semi Local")
	]

	private let _dataService = NBFetchService()
	private let _serverPackUrl = "https://backloop.dev/pack.json"

	var body: some View {
		Group {
			Section {
				Picker(.localized("Installation Type"), systemImage: "server.rack", selection: $_serverMethod) {
					ForEach(_serverMethods.indices, id: \.self) { index in
						Text(_serverMethods[index]).tag(index)
					}
				}
				Toggle(.localized("Only use localhost address"), systemImage: "lifepreserver", isOn: $_ipFix)
					.disabled(_serverMethod != 1)
			}

			Section {
				Button(.localized("Update SSL Certificates"), systemImage: "arrow.down.doc") {
					FR.downloadSSLCertificates(from: _serverPackUrl) { success in
						if !success {
							DispatchQueue.main.async {
								UIAlertController.showAlertWithOk(
									title: .localized("SSL Certificates"),
									message: .localized("Failed to download, check your internet connection and try again.")
								)
							}
						}
					}
				}
			}

			_manifestSection()
		}
		.onChange(of: _manifestSource) { _ in
			_manifestTest = .idle
		}
		.onChange(of: _manifestBase) { _ in
			_manifestTest = .idle
		}
	}

	// MARK: - Manifest server
	@ViewBuilder
	private func _manifestSection() -> some View {
		NBSection(.localized("Manifest Server"), systemName: "list.bullet.rectangle.portrait") {
			Picker(.localized("Source"), systemImage: "server.rack", selection: $_manifestSource) {
				Text(.localized("Default (Built-in)")).tag(ManifestServer.Source.builtIn.rawValue)
				Text(.localized("Official (api.palera.in, offline)")).tag(ManifestServer.Source.official.rawValue)
				Text(.localized("Custom")).tag(ManifestServer.Source.custom.rawValue)
			}

			if _manifestSource == ManifestServer.Source.custom.rawValue {
				TextField(.localized("https://example.com"), text: $_manifestBase)
					.keyboardType(.URL)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()

				if !ManifestServer.isCustomValid {
					Label(
						.localized("Enter a full address starting with https://. While invalid, the built-in server is used."),
						systemImage: "exclamationmark.triangle.fill"
					)
					.font(.caption)
					.foregroundStyle(.red)
				}
			}

			Button {
				_testManifestServer()
			} label: {
				HStack(spacing: 8) {
					Label(.localized("Test Connection"), systemImage: "antenna.radiowaves.left.and.right")
					Spacer(minLength: 8)
					_manifestTestBadge()
				}
			}
			.disabled(_manifestTest == .testing)
		} footer: {
			VStack(alignment: .leading, spacing: 4) {
				Text(.localized("Used to build the OTA install manifest (itms-services). Keep it on Default unless you host your own manifest server."))
				HStack(spacing: 2) {
					Text(.localized("In use:"))
					Text(ManifestServer.effectiveBase)
						.textSelection(.enabled)
				}
			}
		}
	}

	@ViewBuilder
	private func _manifestTestBadge() -> some View {
		switch _manifestTest {
		case .idle:
			EmptyView()
		case .testing:
			ProgressView()
				.controlSize(.small)
		case .reachable(let milliseconds):
			Label(.localized("%lld ms", arguments: milliseconds), systemImage: "checkmark.circle.fill")
				.labelStyle(.titleAndIcon)
				.font(.caption)
				.foregroundStyle(.green)
		case .failed(let message):
			Label(message, systemImage: "xmark.circle.fill")
				.font(.caption)
				.foregroundStyle(.red)
				.lineLimit(1)
		}
	}

	private func _testManifestServer() {
		guard let url = URL(string: ManifestServer.effectiveBase + "/health") else {
			_manifestTest = .failed(message: .localized("Server unreachable"))
			return
		}

		_manifestTest = .testing

		var request = URLRequest(url: url)
		request.timeoutInterval = 8
		request.cachePolicy = .reloadIgnoringLocalCacheData

		let start = Date()
		URLSession.shared.dataTask(with: request) { _, response, error in
			DispatchQueue.main.async {
				if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
					_manifestTest = .reachable(milliseconds: Int(Date().timeIntervalSince(start) * 1000))
				} else if let http = response as? HTTPURLResponse {
					_manifestTest = .failed(message: .localized("Server returned status %lld", arguments: http.statusCode))
				} else {
					_manifestTest = .failed(message: error?.localizedDescription ?? .localized("Server unreachable"))
				}
			}
		}.resume()
	}
}
