//
//  ManifestServer.swift
//  Ksign
//
//  P1（2026-11-19）：OTA 安装清单服务可配置化。
//  上游把清单地址写死为 api.palera.in，该服务自 2026-10 起返回 521（源站不可用），
//  「半本地」安装会停在取清单这一步（日志只有 GET /install，没有 .ipa 下载）。
//  这里改成三档：内置（自建）/ 官方 / 自定义 —— 第三方再挂也不用重新出包。
//
//  自建服务：45.207.214.50 的 /data/services/ksign-plist（systemd: ksign-plist），
//  公网入口 https://ksign.pipicore.cn/genPlist（Cloudflare -> xray fallback -> nginx:8443）。
//

import Foundation

enum ManifestServer {
	/// 内置默认：自建清单服务
	static let builtInBase = "https://ksign.pipicore.cn"
	/// 上游官方：2026-10 起不可用，保留仅为需要时切回
	static let officialBase = "https://api.palera.in"

	enum Source: Int, CaseIterable {
		case builtIn = 0
		case official = 1
		case custom = 2
	}

	/// AppStorage / UserDefaults 键（设置页与安装链路共用，避免两处字符串漂移）
	enum Keys {
		static let source = "Feather.manifestServerSource"
		static let customBase = "Feather.manifestServerBase"
	}

	static var source: Source {
		get { Source(rawValue: UserDefaults.standard.integer(forKey: Keys.source)) ?? .builtIn }
		set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.source) }
	}

	static var customBase: String {
		get { UserDefaults.standard.string(forKey: Keys.customBase) ?? "" }
		set { UserDefaults.standard.set(newValue, forKey: Keys.customBase) }
	}

	/// 当前生效的基础地址（不含 `/genPlist` 路径）
	static var effectiveBase: String {
		switch source {
		case .builtIn:
			return builtInBase
		case .official:
			return officialBase
		case .custom:
			return normalized(customBase) ?? builtInBase
		}
	}

	static var isCustomValid: Bool {
		normalized(customBase) != nil
	}

	/// 规范化用户输入：去空白、去尾部 `/`、允许直接粘贴带 `/genPlist` 的完整地址。
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
