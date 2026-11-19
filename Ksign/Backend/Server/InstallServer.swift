//
//  InstallServer.swift
//  Ksign
//
//  安装服务器（2026-11-19）：
//  半本地安装的 OTA 清单不再写死第三方地址。候选 = 内置 + 自定义，
//  打开设置页/启动时自动测速，自动使用延迟最低的一台（见 InstallServerProbe）。
//
//  内置服务：45.207.214.50 的 /data/services/ksign-plist（systemd: ksign-plist），
//  公网入口 https://ksign.pipicore.cn/genPlist（Cloudflare -> xray fallback -> nginx:8443）。
//

import Foundation

enum InstallServer {
	/// 内置安装服务器（自建）
	static let builtInBase = "https://ksign.pipicore.cn"
	/// 上游原来的清单服务。2026-10 起 521，但保留在候选里：
	/// 哪天恢复了就自动参与测速，不恢复就显示「不可用」，不影响选择。
	static let legacyBase = "https://api.palera.in"

	enum Keys {
		/// 当前选中的服务器（自动挑延迟最低的）
		static let selected = "Feather.installServerBase"
		/// 用户自己填的服务器
		static let custom = "Feather.installServerCustom"
	}

	/// 参与自动选择的服务器（内置 + 原有服务 + 自定义，去重）
	static var candidates: [String] {
		var list = [builtInBase, legacyBase]
		if let custom = normalizedCustomBase, !list.contains(custom) {
			list.append(custom)
		}
		return list
	}

	static var customBase: String {
		get { UserDefaults.standard.string(forKey: Keys.custom) ?? "" }
		set { UserDefaults.standard.set(newValue, forKey: Keys.custom) }
	}

	static var normalizedCustomBase: String? {
		normalized(customBase)
	}

	/// 空输入不算错；填了就必须是合法 https 地址
	static var isCustomInputValid: Bool {
		let trimmed = customBase.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty || normalizedCustomBase != nil
	}

	/// 当前实际使用的服务器：选中值仍在候选里就用它，否则用内置
	static var effectiveBase: String {
		let selected = UserDefaults.standard.string(forKey: Keys.selected) ?? ""
		return candidates.contains(selected) ? selected : builtInBase
	}

	static func setSelected(_ base: String) {
		guard candidates.contains(base) else { return }
		UserDefaults.standard.set(base, forKey: Keys.selected)
	}

	/// 规范化输入：去空白、去尾部 `/`、允许直接粘贴带 `/genPlist` 的完整地址。
	/// 只接受 https + 有 host 的地址（iOS 只接受 HTTPS 的安装清单）。
	static func normalized(_ raw: String) -> String? {
		var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		while value.hasSuffix("/") {
			value.removeLast()
		}
		if value.lowercased().hasSuffix("/genplist") {
			value = String(value.dropLast("/genPlist".count))
			while value.hasSuffix("/") {
				value.removeLast()
			}
		}

		guard
			!value.isEmpty,
			let comps = URLComponents(string: value),
			comps.scheme?.lowercased() == "https",
			let host = comps.host,
			!host.isEmpty,
			comps.query == nil,
			comps.fragment == nil
		else {
			return nil
		}

		return comps.string
	}
}
