//
//  AppIconView.swift
//  Ksign
//
//  Created by Nagata Asami on 6/28/25.
//

import SwiftUI
import NimbleViews

// MARK: - Models
struct AppIconOption {
    let id: String
    let title: String
    let subtitle: String
    /// 预览图必须用独立的 imageset：appiconset 不能在运行时用 UIImage(named:) 取，
    /// 之前取不到就回退成「当前图标」，导致 7 行预览全是一样的颜色。
    let previewImageName: String
    let alternateIconName: String?
}

// MARK: - View
struct AppIconView: View {
    @State private var selectedIcon: String? = UIApplication.shared.alternateIconName
    
    private let appIcons: [AppIconOption] = [
        AppIconOption(
            id: "purple",
            title: "Purple",
            subtitle: "Ksign",
            previewImageName: "AppIconPreview",
            alternateIconName: nil
        ),
        AppIconOption(
            id: "red",
            title: "Red",
            subtitle: "Ksign",
            previewImageName: "AppIconPreviewRed",
            alternateIconName: "AppIconRed"
        ),
        AppIconOption(
            id: "pink",
            title: "Pink",
            subtitle: "Ksign",
            previewImageName: "AppIconPreviewPink",
            alternateIconName: "AppIconPink"
        ),
        AppIconOption(
            id: "blue",
            title: "Blue",
            subtitle: "Ksign",
            previewImageName: "AppIconPreviewBlue",
            alternateIconName: "AppIconBlue"
        ),
        AppIconOption(
            id: "green",
            title: "Green",
            subtitle: "Ksign",
            previewImageName: "AppIconPreviewGreen",
            alternateIconName: "AppIconGreen"
        ),
        AppIconOption(
            id: "orange",
            title: "Orange",
            subtitle: "Ksign",
            previewImageName: "AppIconPreviewOrange",
            alternateIconName: "AppIconOrange"
        ),
        AppIconOption(
            id: "black",
            title: "Black",
            subtitle: "Ksign",
            previewImageName: "AppIconPreviewBlack",
            alternateIconName: "AppIconBlack"
        ),
    ]
    
    // MARK: Body
    var body: some View {
        NBList(.localized("App Icon")) {
            NBSection(.localized("Available Icons")) {
                ForEach(appIcons, id: \.id) { iconOption in
                    _iconCell(for: iconOption)
                }
            }
        }
        .onAppear {
            selectedIcon = UIApplication.shared.alternateIconName
        }
    }
}

// MARK: - View extension
extension AppIconView {
    @ViewBuilder
    private func _iconCell(for iconOption: AppIconOption) -> some View {
        Button {
            _changeAppIcon(to: iconOption)
        } label: {
            HStack(spacing: 12) {
                if let image = UIImage(named: iconOption.previewImageName) {
                    Image(uiImage: image)
                        .appIconStyle(size: 60)
                } else {
                    Image("App_Unknown")
                        .appIconStyle(size: 60)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(String.localized(iconOption.title))
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(String.localized(iconOption.subtitle))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if selectedIcon == iconOption.alternateIconName {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .font(.headline)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func _changeAppIcon(to iconOption: AppIconOption) {
        guard selectedIcon != iconOption.alternateIconName else { return }
        
//        guard UIApplication.shared.supportsAlternateIcons else {
//            print("Alternate icons are not supported on this device")
//            return
//        }
        
        UIApplication.shared.setAlternateIconName(iconOption.alternateIconName) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to change app icon: \(error.localizedDescription)")
                } else {
                    self.selectedIcon = iconOption.alternateIconName
                    print("Successfully changed app icon to: \(iconOption.alternateIconName ?? "primary")")
                }
            }
        }
    }
} 
