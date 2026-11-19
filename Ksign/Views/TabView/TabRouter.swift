//
//  TabRouter.swift
//  Ksign
//
//  分享导入自动跳资料库（2026-11-19）。
//  iOS 18+ 的 ExtendedTabbarView 和旧版 TabbarView 共用这一个选择源，
//  SceneDelegate 收到 ksign://share-import 并真正导入文件后切到资料库。
//
//  不落盘：冷启动仍然按 TabEnum.defaultTabs 第一项（资料库）显示，
//  和「启动默认页改为资料库」的行为一致；只有进程活着的这次会话会被切走。
//

import Foundation
import Combine

final class TabRouter: ObservableObject {
	static let shared = TabRouter()

	/// TabEnum.rawValue；来源分组的 tab 用 "sources.all" / "source.<id>"。
	@Published var selection: String = TabEnum.library.rawValue

	func select(_ tab: TabEnum) {
		let value = tab.rawValue
		if Thread.isMainThread {
			selection = value
		} else {
			DispatchQueue.main.async { [weak self] in
				self?.selection = value
			}
		}
	}
}
