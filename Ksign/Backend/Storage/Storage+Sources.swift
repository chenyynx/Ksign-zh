//
//  Storage+Sources.swift
//  Feather
//
//  Created by samara on 12.04.2025.
//

import CoreData
import AltSourceKit

// MARK: - Class extension: Sources
extension Storage {
	/// Retrieve sources in an array, we don't normally need this in swiftUI but we have it for the copy sources action
	func getSources() -> [AltSource] {
		let request: NSFetchRequest<AltSource> = AltSource.fetchRequest()
		return (try? context.fetch(request)) ?? []
	}
	
	func addSource(
		_ url: URL,
		name: String? = "Unknown",
		identifier: String,
		iconURL: URL? = nil,
		deferSave: Bool = false,
		isBuiltIn: Bool = false,
		completion: @escaping (Error?) -> Void
	) {
		if sourceExists(identifier) {
			completion(nil)
			print("ignoring \(identifier)")
			return
		}
		
		let new = AltSource(context: context)
		new.name = name
		new.date = Date()
		new.identifier = identifier
		new.sourceURL = url
		new.iconURL = iconURL
		new.setValue(isBuiltIn, forKey: "isBuiltIn")
		
		do {
			if !deferSave {
				try context.save()
			}
			completion(nil)
		} catch {
			completion(error)
		}
	}
	
	func addSource(
		_ url: URL,
		repository: ASRepository,
		id: String = "",
		deferSave: Bool = false,
		isBuiltIn: Bool = false,
		completion: @escaping (Error?) -> Void
	) {
		addSource(
			url,
			name: repository.name,
			identifier: !id.isEmpty
						? id
						: (repository.id ?? url.absoluteString),
			iconURL: repository.currentIconURL,
			deferSave: deferSave,
			isBuiltIn: isBuiltIn,
			completion: completion
		)
	}

	func addSources(
		repos: [URL: ASRepository],
		completion: @escaping (Error?) -> Void
	) {
		for (url, repo) in repos {
			addSource(
				url,
				repository: repo,
				deferSave: true,
				completion: { error in
					if let error {
						completion(error)
					}
				}
			)
		}
		
        saveContext()
        completion(nil)
	}


	/// 写入内置源，全部结束后回报成功写入的数量。
	/// 调用方（AppDelegate）只在 successCount > 0 时记录初始化完成，
	/// 否则下次启动继续重试——离线首次启动不会把「已初始化」永久置上。
	func addBuiltInSources(completion: ((Int) -> Void)? = nil) {
		let builtInSourceURLs = [
            "https://raw.githubusercontent.com/Nyasami/Ksign/refs/heads/main/repo.json",
            "https://decrypt.stream/feather.json",
            "https://community-apps.sidestore.io/sidecommunity.json",
            "https://github.com/LiveContainer/LiveContainer/releases/download/1.0/apps.json",
            "https://alt.crystall1ne.dev"
		]

		let group = DispatchGroup()
		let counterQueue = DispatchQueue(label: "ksign.builtInSources.counter")
		var successCount = 0

		for urlString in builtInSourceURLs {
			group.enter()
			FR.handleSource(urlString, isBuiltIn: true, silent: true) { success in
				if success {
					counterQueue.sync { successCount += 1 }
				}
				group.leave()
			}
		}

		group.notify(queue: .main) {
			completion?(counterQueue.sync { successCount })
		}
	}

	func deleteSource(for source: AltSource) {
		context.delete(source)
		saveContext()
	}

	func sourceExists(_ identifier: String) -> Bool {
		let fetchRequest: NSFetchRequest<AltSource> = AltSource.fetchRequest()
		fetchRequest.predicate = NSPredicate(format: "identifier == %@", identifier)

		do {
			let count = try context.count(for: fetchRequest)
			return count > 0
		} catch {
			print("Error checking if repository exists: \(error)")
			return false
		}
	}
}
