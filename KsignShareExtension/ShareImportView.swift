//
//  ShareImportView.swift
//  KsignShareExtension
//

import SwiftUI

struct SharedFile: Identifiable {
	let id = UUID()
	let name: String
	let url: URL
	let size: Int64

	var sizeText: String {
		ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
	}
}

struct ShareImportView: View {
	@ObservedObject var model: ShareImportModel
	let onCancel: () -> Void

	var body: some View {
		NavigationStack {
			List {
				Section {
					if model.files.isEmpty {
						Text(model.status.isEmpty ? "没有可导入的文件" : model.status)
							.foregroundColor(.secondary)
					} else {
						ForEach(model.files) { file in
							HStack {
								Image(systemName: "doc.zipper")
									.foregroundColor(.accentColor)
								VStack(alignment: .leading, spacing: 2) {
									Text(file.name).lineLimit(1)
									Text(file.sizeText)
										.font(.caption)
										.foregroundColor(.secondary)
								}
							}
						}
					}
				} header: {
					Text("待导入")
				} footer: {
					if !model.status.isEmpty {
						Text(model.status)
					}
				}
			}
			.navigationTitle("导入到 Ksign")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("取消", action: onCancel)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("导入") {
						model.startImport()
					}
					.disabled(model.files.isEmpty || model.isImporting)
				}
			}
			.overlay {
				if model.isImporting {
					ProgressView("正在导入…")
						.padding()
						.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
				}
			}
		}
	}
}
