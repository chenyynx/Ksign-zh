//
//  CertificatesAddView.swift
//  Feather
//
//  Created by samara on 15.04.2025.
//

import SwiftUI
import NimbleViews
import UniformTypeIdentifiers

// MARK: - View
struct CertificatesAddView: View {
	@Environment(\.dismiss) private var dismiss
	
	@State private var _p12URL: URL? = nil
	@State private var _provisionURL: URL? = nil
	@State private var _p12Password: String = ""
	@State private var _certificateName: String = ""
	
	@State private var _isImportingP12Presenting = false
	@State private var _isImportingMobileProvisionPresenting = false
	@State private var _alertTitle: String = ""
	@State private var _alertMessage: String = ""
	@State private var _isAlertPresenting = false
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("New Certificate"), displayMode: .inline) {
			Form {
				NBSection(.localized("Files")) {
					_importButton(.localized("Import Certificate File"), file: _p12URL) {
						_isImportingP12Presenting = true
					}
					_importButton(.localized("Import Provisioning File"), file: _provisionURL) {
						_isImportingMobileProvisionPresenting = true
					}
				}
				NBSection(.localized("Password")) {
					SecureField(.localized("Enter Password"), text: $_p12Password)
				} footer: {
					Text(.localized("Enter the password associated with the private key. Leave it blank if theres no password required."))
				}
				
				Section {
					TextField(.localized("Nickname (Optional)"), text: $_certificateName)
				}
			}
			.toolbar {
				NBToolbarButton(role: .cancel)
				
				NBToolbarButton(
					.localized("Save"),
					style: .text,
					placement: .confirmationAction
				) {
					_saveCertificate()
				}
			}
			.sheet(isPresented: $_isImportingP12Presenting) {
				FileImporterRepresentableView(
					allowedContentTypes: [UTType.p12],
					onDocumentsPicked: { urls in
						guard let selectedFileURL = urls.first else { return }
						self._p12URL = selectedFileURL
					}
				)
			}
			.sheet(isPresented: $_isImportingMobileProvisionPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes: [UTType.mobileProvision],
					onDocumentsPicked: { urls in
						guard let selectedFileURL = urls.first else { return }
						self._provisionURL = selectedFileURL
					}
				)
			}
			.alert(isPresented: $_isAlertPresenting) {
				Alert(
					title: Text(_alertTitle),
					message: Text(_alertMessage),
					dismissButton: .default(Text(.localized("OK")))
				)
			}
		}
	}
}

// MARK: - Extension: View
extension CertificatesAddView {
	@ViewBuilder
	private func _importButton(
		_ title: String,
		file: URL?,
		action: @escaping () -> Void
	) -> some View {
		Button {
			action()
		} label: {
			HStack(spacing: 8) {
				Text(title)
				Spacer(minLength: 8)
				if let file {
					Text(file.lastPathComponent)
						.font(.footnote)
						.foregroundColor(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
					Image(systemName: "checkmark.circle.fill")
						.font(.footnote)
						.foregroundColor(.green)
				}
			}
		}
		.foregroundColor(file == nil ? .accentColor : .primary)
	}
}

// MARK: - Extension: View (import)
extension CertificatesAddView {
	private func _showAlert(_ title: String, _ message: String) {
		_alertTitle = title
		_alertMessage = message
		_isAlertPresenting = true
	}
	
	/// Copies a picked file into the sandbox's temp folder.
	/// Picker URLs are security scoped, and reading them without
	/// start/stopAccessingSecurityScopedResource() silently fails.
	private func _materialize(_ url: URL) -> URL {
		let fm = FileManager.default
		let didStart = url.startAccessingSecurityScopedResource()
		defer {
			if didStart {
				url.stopAccessingSecurityScopedResource()
			}
		}
		
		let destination = fm.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.appendingPathComponent(url.lastPathComponent)
		
		do {
			try fm.createDirectory(
				at: destination.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try fm.copyItem(at: url, to: destination)
			return destination
		} catch {
			return url
		}
	}
	
	private func _saveCertificate() {
		guard let p12Raw = _p12URL else {
			_showAlert("未选择证书文件", "请先点「导入证书文件」选择 .p12 文件。")
			return
		}
		
		guard let provisionRaw = _provisionURL else {
			_showAlert("未选择描述文件", "请先点「导入描述文件」选择 .mobileprovision 文件。签名需要证书和描述文件同时存在。")
			return
		}
		
		let p12URL = _materialize(p12Raw)
		let provisionURL = _materialize(provisionRaw)
		
		guard FR.checkPasswordForCertificate(
			for: p12URL,
			with: _p12Password,
			using: provisionURL
		) else {
			_showAlert(
				.localized("Bad Password"),
				"证书密码不正确，或者描述文件与证书不匹配。请检查后重试。"
			)
			return
		}
		
		FR.handleCertificateFiles(
			p12URL: p12URL,
			provisionURL: provisionURL,
			p12Password: _p12Password,
			certificateName: _certificateName
		) { error in
			if let error {
				_showAlert("导入证书失败", error.localizedDescription)
			} else {
				dismiss()
			}
		}
	}
}
