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

struct ServerView: View {
	@AppStorage("Feather.ipFix") private var _ipFix: Bool = false
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 1

	// 安装服务器：打开本页自动测速，自动用延迟最低的一台
	@AppStorage(InstallServer.Keys.custom) private var _customBase: String = ""
	@ObservedObject private var _probe = InstallServerProbe.shared
	@State private var _pendingProbe: DispatchWorkItem?

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

			_installServerSection()
		}
		.onAppear {
			_probe.probe()
		}
		.onChange(of: _customBase) { _ in
			// 输入防抖：停手 0.8s 再测，免得每敲一个字发一次请求
			_pendingProbe?.cancel()
			let work = DispatchWorkItem { _probe.probe() }
			_pendingProbe = work
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
		}
	}

	// MARK: - Install server
	@ViewBuilder
	private func _installServerSection() -> some View {
		NBSection(.localized("Install Server"), systemName: "server.rack") {
			ForEach(InstallServer.candidates, id: \.self) { base in
				_installServerRow(base)
			}

			TextField(.localized("Custom server URL"), text: $_customBase)
				.keyboardType(.URL)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()

			if !InstallServer.isCustomInputValid {
				Label(
					.localized("Invalid URL. Use a full address starting with https://."),
					systemImage: "exclamationmark.triangle.fill"
				)
				.font(.caption)
				.foregroundStyle(.red)
			}

			Button {
				_probe.probe()
			} label: {
				Label(.localized("Speed Test Again"), systemImage: "arrow.clockwise")
			}
			.disabled(_probe.isProbing)
		} footer: {
			VStack(alignment: .leading, spacing: 4) {
				Text(.localized("Speed-tests automatically when this page opens and uses the lowest-latency server."))
				HStack(spacing: 2) {
					Text(.localized("In use:"))
					Text(InstallServer.effectiveBase)
						.textSelection(.enabled)
				}
			}
		}
	}

	@ViewBuilder
	private func _installServerRow(_ base: String) -> some View {
		HStack(spacing: 10) {
			Image(systemName: base == InstallServer.builtInBase ? "server.rack" : "link")
				.foregroundStyle(.secondary)
				.frame(width: 22)

			Text(URL(string: base)?.host ?? base)
				.lineLimit(1)
				.truncationMode(.middle)

			Spacer(minLength: 8)

			_latencyBadge(for: base)

			if InstallServer.effectiveBase == base {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.tint)
			}
		}
	}

	@ViewBuilder
	private func _latencyBadge(for base: String) -> some View {
		switch _probe.states[base] {
		case .none:
			Text("—")
				.font(.caption)
				.foregroundStyle(.secondary)
		case .some(.probing):
			ProgressView()
				.controlSize(.small)
		case .some(.ok(let milliseconds)):
			Text(String.localized("%lld ms", arguments: milliseconds))
				.font(.caption.monospacedDigit())
				.foregroundStyle(.green)
		case .some(.failed):
			Text(.localized("Unavailable"))
				.font(.caption)
				.foregroundStyle(.red)
		}
	}
}
