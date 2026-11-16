//
//  SigningAppPropertiesView.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningPropertiesView: View {
	@Environment(\.dismiss) var dismiss

	@State private var text: String = ""

	var saveButtonDisabled: Bool {
		// 标识符页（带 source）允许“不改文本、只换来源”，所以始终可保存。
		text == initialValue && source == nil
	}

	var title: String
	var initialValue: String
	var certAppId: String? = nil
	var originalAppId: String? = nil
	@Binding var bindingValue: String?
	/// "certificate" / "original" / "custom"；只有标识符页会传。
	var source: Binding<String?>? = nil

	private var isCertificateValue: Bool {
		guard let certAppId else { return false }
		return text == certAppId
	}

	private var isOriginalValue: Bool {
		guard let originalAppId else { return false }
		return text == originalAppId
	}

	// MARK: Body
	var body: some View {
		NBList(title) {
			TextField(initialValue, text: $text)
				.textInputAutocapitalization(.none)
			if certAppId != nil || originalAppId != nil {
				Section {
					if let certAppId {
						Button {
							text = certAppId
						} label: {
							HStack {
								Text(.localized("Matching Certificate's App ID"))
								Spacer()
								if isCertificateValue {
									Image(systemName: "checkmark")
										.foregroundStyle(Color.accentColor)
								}
							}
						}
					}
					if let originalAppId {
						Button {
							text = originalAppId
						} label: {
							HStack {
								Text("使用 App 原始 ID")
								Spacer()
								if isOriginalValue {
									Image(systemName: "checkmark")
										.foregroundStyle(Color.accentColor)
								}
							}
						}
					}
				} footer: {
					Text("证书 App ID 可以使用证书里的权限；原始 ID 保留 IPA 自带的标识符。直接输入其他值即为自定义。")
				}
			}
		}
		.toolbar {
			NBToolbarButton(
				.localized("Save"),
				style: .text,
				placement: .topBarTrailing,
				isDisabled: saveButtonDisabled
			) {
				if !saveButtonDisabled {
					bindingValue = text
					updateSource()
					dismiss()
				}
			}
		}
		.onAppear {
			text = initialValue
		}
	}

	private func updateSource() {
		guard let source else { return }
		if let certAppId, text == certAppId {
			source.wrappedValue = "certificate"
		} else if let originalAppId, text == originalAppId {
			source.wrappedValue = "original"
		} else {
			source.wrappedValue = "custom"
		}
	}
}
