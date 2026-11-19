//
//  Server+Compute.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import UIKit.UIGraphicsImageRenderer

extension ServerInstaller {
	var plistEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = ServerInstaller.getServerMethod() == 1 ? "http" : "https"
		comps.host = Self.sni
		comps.path = "/\(id).plist"
		comps.port = port
		return comps.url!
	}

	var payloadEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = ServerInstaller.getServerMethod() == 1 ? "http" : "https"
		comps.host = Self.sni
		comps.path = "/\(id).ipa"
		comps.port = port
		return comps.url!
	}
	
	var pageEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = ServerInstaller.getServerMethod() == 1 ? "http" : "https"
		comps.host = Self.sni
		comps.path = "/install"
		comps.port = port
		return comps.url!
	}
	
	/// 清单地址取自设置（内置自建 / 官方 / 自定义），见 ManifestServer。
	var externalServerLink: String {
		guard
			let identifier = app.identifier,
			let name = app.name,
			let version = app.version
		else {
			return ""
		}

		// 不用 URLComponents：它对 query 值里的 `&`/`+` 不编码，会被服务端当成新参数。
		var allowed = CharacterSet.urlQueryAllowed
		allowed.remove(charactersIn: "&=+?#%")
		func encode(_ value: String) -> String {
			value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
		}

		let baseUrl = ManifestServer.effectiveBase
			+ "/genPlist?bundleid=\(encode(identifier))"
			+ "&name=\(encode(name))"
			+ "&version=\(encode(version))"
			+ "&fetchurl=\(encode(payloadEndpoint.absoluteString))"

		let encodedBaseUrl = baseUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
		let finalEncodedUrl = encodedBaseUrl.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

		return finalEncodedUrl
	}

	var iTunesLink: String {
		_iTunesLink(with: plistEndpoint.absoluteString)
	}
	
	var iTunesLinkExternal: String {
		_iTunesLink(with: externalServerLink)
	}
	
	private func _iTunesLink(with url: String) -> String {
		return "itms-services://?action=download-manifest&url=\(url)"
	}

	var displayImageSmallEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = Self.sni
		comps.path = "/app57x57.png"
		comps.port = port
		return comps.url!
	}

	var displayImageLargeEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = Self.sni
		comps.path = "/app512x512.png"
		comps.port = port
		return comps.url!
	}
	
	var displayImageSmallData: Data {
		_createIcon(57)
	}
	
	var displayImageLargeData: Data {
		_createIcon(512)
	}
	
	private func _createIcon(_ r: CGFloat) -> Data {
		let renderer = UIGraphicsImageRenderer(size: .init(width: r, height: r))
		let image = renderer.image { ctx in
			UIColor.accent.setFill()
			ctx.fill(.init(x: 0, y: 0, width: r, height: r))
		}
		return image.pngData()!
	}

	var html: String {
		"""
		<html style="background-color: black;">
		<script type="text/javascript">window.location="\(iTunesLinkExternal)"</script>
		</html>
		"""
	}

	var installManifest: [String: Any] {[
		"items": [[
			"assets": [
				[
					"kind": "software-package",
					"url": payloadEndpoint.absoluteString,
				],
				[
					"kind": "display-image",
					"url": "https://raw.githubusercontent.com/Nyasami/Ksign/refs/heads/main/Ksign/Resources/Assets.xcassets/AppIcons/AppIcon.appiconset/Ksign-default.png",
				],
			],
			"metadata": [
				"bundle-identifier": app.identifier,
				"bundle-version": app.version,
				"kind": "software",
				"title": app.name,
			],
		],],
	]}

	var installManifestData: Data {
		(try? PropertyListSerialization.data(
			fromPropertyList: installManifest,
			format: .xml,
			options: .zero
		)) ?? .init()
	}
}
