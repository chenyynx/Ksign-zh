//
//  StatusViewModel.swift
//  Feather
//
//  Created by samara on 24.04.2025.
//

import Foundation
import Combine
import IDeviceSwift

extension InstallerStatusViewModel {
	
	var statusImage: String {
		switch status {
		case .none: return "archivebox.fill"
		case .ready: return "app.gift"
		case .sendingManifest, .sendingPayload: return "paperplane.fill"
		case .installing: return "square.and.arrow.down"
		case .completed: return "app.badge.checkmark"
		case .broken: return "exclamationmark.triangle.fill"
		}
	}
	
	var statusLabel: String {
		switch status {
		case .none: return String.localized("Packaging")
		case .ready: return String.localized("Ready")
		case .sendingManifest: return String.localized("Sending Manifest")
		case .sendingPayload: return String.localized("Sending Payload")
		case .installing: return String.localized("Installing")
		case .completed: return String.localized("Completed")
		case .broken: return String.localized("Error")
		}
	}
}
