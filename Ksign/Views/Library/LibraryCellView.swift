//
//  LibraryAppIconView.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import SwiftUI
import NimbleExtensions
import NimbleViews

// MARK: - View
struct LibraryCellView: View {
	@AppStorage("Feather.libraryCellAppearance") private var _libraryCellAppearance: Int = 0
	/// 是否在每行下方显示导入/签名时间（设置 → 外观 → 资料库 可开关）
	@AppStorage("Feather.showImportDate") private var _showImportDate: Bool = true
    @Environment(\.editMode) private var editMode
	var certInfo: Date.ExpirationInfo? {
		Storage.shared.getCertificate(from: app)?.expiration?.expirationInfo()
	}
	
	var app: AppInfoPresentable
	@Binding var selectedInfoAppPresenting: AnyApp?
	@Binding var selectedSigningAppPresenting: AnyApp?
	@Binding var selectedInstallAppPresenting: AnyApp?
	@Binding var selectedAppDylibsPresenting: AnyApp?
	@Binding var selectedApps: Set<String>
	@State private var _showActionSheet = false
	
	private var _isSelected: Bool {
		selectedApps.contains(app.uuid ?? "")
	}
	// MARK: Body
	var body: some View {
        let isEditing = editMode?.wrappedValue == .active
        HStack(spacing: 9) {
			if isEditing {
				Button {
					_toggleSelection()
				} label: {
					Image(systemName: _isSelected ? "checkmark.circle.fill" : "circle")
						.foregroundColor(_isSelected ? .accentColor : .secondary)
						.font(.title2)
				}
				.buttonStyle(.borderless)
			}
			
			FRAppIconView(app: app, size: 57)
			
			// 标题 / 版本 • Bundle ID / 导入或签名时间（时间单独一行小字，外观里可开关）
			VStack(alignment: .leading, spacing: 2) {
				Text(app.name ?? .localized("Unknown"))
					.font(.headline)
				Text(_desc)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
				if let dateLine = _dateLine {
					Text(dateLine)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			
			Spacer()
			
			if !isEditing {
				if app.isSigned, let certInfo = certInfo {
					HStack(spacing: 4) {
						Image(systemName: "clock")
							.font(.system(size: 11))
	                    Text(certInfo.formatted)
							.font(.system(size: 12))
							.fontWeight(.semibold)
					}
					.foregroundColor(.white)
					.padding(.horizontal, 10)
					.padding(.vertical, 5)
					.background(certInfo.color)
					.clipShape(Capsule())
					.padding(.trailing, 4)
				}
				
				Image(systemName: "chevron.right")
					.foregroundColor(.secondary)
					.font(.footnote)
			}
		}
		.scaleEffect(_isSelected ? 0.98 : 1.0)
		.contentShape(Rectangle())
		.onTapGesture {
			if isEditing {
				_toggleSelection()
			} else {
				_showActionSheet = true
			}
		}
		.confirmationDialog(
			app.name ?? .localized("Unknown"),
			isPresented: $_showActionSheet,
			titleVisibility: .visible
		) {
			if !isEditing {
				_actionSheetButtons(for: app)
			}
		}
		.swipeActions {
			if !isEditing {
				_actions(for: app)
			}
		}
		.contextMenu {
			if !isEditing {
				_contextActions(for: app)
				Divider()
				_contextActionsExtra(for: app)
				Divider()
				_actions(for: app)
			}
		}
	}
	
	private var _desc: String {
		if
			let version = app.version,
			let id = app.identifier
		{
			return "\(version) • \(id)"
		} else {
			return .localized("Unknown")
		}
	}

	/// 独立一行的日期文案；关闭开关或没有日期时返回 nil，整行不渲染。
	private var _dateLine: String? {
		guard _showImportDate, let date = _date else { return nil }
		let formatted = date.formatted(date: .numeric, time: .shortened)
		return app.isSigned
			? .localized("Signed on %@", arguments: formatted)
			: .localized("Imported on %@", arguments: formatted)
	}

	/// 正常取 Core Data 的 date；旧数据缺 date 时退回应用目录的创建时间，保证这行有内容。
	private var _date: Date? {
		if let date = app.date { return date }
		guard let url = Storage.shared.getUuidDirectory(for: app) else { return nil }
		return (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
	}
	
	private func _toggleSelection() {
		guard let uuid = app.uuid else { return }
		
		let impactFeedback = UIImpactFeedbackGenerator(style: .light)
		impactFeedback.impactOccurred()
		
		withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)) {
			if _isSelected {
				selectedApps.remove(uuid)
			} else {
				selectedApps.insert(uuid)
			}
		}
	}
}

// MARK: - Extension: View
extension LibraryCellView {
	@ViewBuilder
	private func _actions(for app: AppInfoPresentable) -> some View {
		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			Storage.shared.deleteApp(for: app)
		}
	}
	
	@ViewBuilder
	private func _contextActions(for app: AppInfoPresentable) -> some View {
		Button(.localized("Get Info"), systemImage: "info.circle") {
			selectedInfoAppPresenting = AnyApp(base: app)
		}
	}
	
	@ViewBuilder
	private func _contextActionsExtra(for app: AppInfoPresentable) -> some View {
		if app.isSigned {
			if let id = app.identifier {
				Button(.localized("Open"), systemImage: "app.badge.checkmark") {
					UIApplication.openApp(with: id)
				}
			}
			Button(.localized("Install"), systemImage: "square.and.arrow.down") {
				selectedInstallAppPresenting = AnyApp(base: app)
			}
			Button(.localized("Re-sign"), systemImage: "signature") {
				selectedSigningAppPresenting = AnyApp(base: app)
			}
			Button(.localized("Export"), systemImage: "square.and.arrow.up") {
				selectedInstallAppPresenting = AnyApp(base: app, archive: true)
			}
		} else {
			Button(.localized("Install"), systemImage: "square.and.arrow.down") {
				selectedInstallAppPresenting = AnyApp(base: app)
			}
		}
	}
	
	@ViewBuilder
	private func _actionSheetButtons(for app: AppInfoPresentable) -> some View {
		if app.isSigned {
			Button(.localized("Install")) {
				selectedInstallAppPresenting = AnyApp(base: app)
			}
			
			if let id = app.identifier {
				Button(.localized("Open")) {
					UIApplication.openApp(with: id)
				}
			}
			
			Button(.localized("Re-sign")) {
				selectedSigningAppPresenting = AnyApp(base: app)
			}
			
			Button(.localized("Export")) {
				selectedInstallAppPresenting = AnyApp(base: app, archive: true)
			}
		} else {
			Button(.localized("Sign & Install")) {
				selectedSigningAppPresenting = AnyApp(base: app, signAndInstall: true)
			}
			
			Button(.localized("Sign")) {
				selectedSigningAppPresenting = AnyApp(base: app)
			}
			
			Button(.localized("Export")) {
				selectedInstallAppPresenting = AnyApp(base: app, archive: true)
			}
		}
		
		Button(.localized("Show Dylibs")) {
			selectedAppDylibsPresenting = AnyApp(base: app)
		}
		
		Button(.localized("Get Info")) {
			selectedInfoAppPresenting = AnyApp(base: app)
		}
		
		Button(.localized("Delete"), role: .destructive) {
			Storage.shared.deleteApp(for: app)
		}
	}
	
	@ViewBuilder
	private func _buttonActions(for app: AppInfoPresentable) -> some View {
		Group {
			if app.isSigned {
				Button {
					selectedInstallAppPresenting = AnyApp(base: app)
				} label: {
					FRExpirationPillView(
						title: .localized("Install"),
						showOverlay: _libraryCellAppearance == 0,
						expiration: certInfo
					)
				}
			} else {
				Button {
					selectedSigningAppPresenting = AnyApp(base: app)
				} label: {
					FRExpirationPillView(
						title: .localized("Sign"),
						showOverlay: true,
						expiration: nil
					)
				}
			}
		}
		.buttonStyle(.borderless)
	}
}
