//
//  InstallServerProbe.swift
//  Ksign
//
//  安装服务器测速（2026-11-19）：打开设置页/启动时并发请求各候选服务器的
//  /genPlist，记录耗时，自动选延迟最低的一台写进 InstallServer.selected。
//  任何一台超时/5xx 都只影响它自己，不会拖住别家。
//

import Foundation
import Combine

final class InstallServerProbe: ObservableObject {
	static let shared = InstallServerProbe()

	enum State: Equatable {
		case probing
		case ok(milliseconds: Int)
		case failed
	}

	@Published private(set) var states: [String: State] = [:]
	@Published private(set) var isProbing = false

	/// 递增代次：旧一轮的结果晚到就丢弃，避免覆盖新一轮
	private var generation = 0

	func probe() {
		let candidates = InstallServer.candidates
		generation += 1
		let current = generation

		isProbing = true
		states = Dictionary(uniqueKeysWithValues: candidates.map { ($0, State.probing) })

		guard !candidates.isEmpty else {
			isProbing = false
			return
		}

		let group = DispatchGroup()

		for base in candidates {
			guard let url = URL(string: base + Self.probePath) else {
				states[base] = .failed
				continue
			}

			group.enter()
			let startedAt = Date()

			var request = URLRequest(url: url)
			request.timeoutInterval = 3
			request.cachePolicy = .reloadIgnoringLocalCacheData

			URLSession.shared.dataTask(with: request) { _, response, _ in
				let state: State
				// 只测到"服务器回应"：2xx/3xx/4xx 都算通，5xx 和网络错误算失败。
				if let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
					state = .ok(milliseconds: Int(Date().timeIntervalSince(startedAt) * 1000))
				} else {
					state = .failed
				}

				// 谁先回来谁先显示，别让慢/挂掉的那台拖住整页
				DispatchQueue.main.async { [weak self] in
					guard let self, self.generation == current else { return }
					self.states[base] = state
					if case .ok = state {
						self._selectLowest(from: self.states)
					}
				}

				group.leave()
			}.resume()
		}

		group.notify(queue: .main) { [weak self] in
			guard let self, self.generation == current else { return }
			self._selectLowest(from: self.states)
			self.isProbing = false
		}
	}

	/// 在已测出的结果里挑延迟最低的一台；失败/未返回的不参与
	private func _selectLowest(from states: [String: State]) {
		let best = states.compactMap { (base, state) -> (String, Int)? in
			if case .ok(let milliseconds) = state {
				return (base, milliseconds)
			}
			return nil
		}.min { $0.1 < $1.1 }?.0

		if let best {
			InstallServer.setSelected(best)
		}
	}

	/// 用 com.ksign.probe 这套无害参数请求真正的清单接口，量的是安装时会走的那条路。
	private static let probePath =
		"/genPlist?bundleid=com.ksign.probe&name=Probe&version=1"
		+ "&fetchurl=https%3A%2F%2Fexample.com%2Fprobe.ipa"
}
