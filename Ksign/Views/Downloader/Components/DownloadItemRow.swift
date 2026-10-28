//
//  DownloadItemRow.swift
//  Ksign
//
//  Created by Nagata Asami on 5/24/25.
//

import SwiftUI
import AltSourceKit

// Download Item Row
struct DownloadItemRow: View {
    let item: DownloadItem
    @Binding var shareItems: [Any]
    var importIpaToLibrary: (DownloadItem) -> Void
    var exportToFiles: (DownloadItem) -> Void
    var deleteItem: (DownloadItem) -> Void

    @State private var showingConfirmationDialog = false

    init(
        item: DownloadItem,
        shareItems: Binding<[Any]>,
        importIpaToLibrary: @escaping (DownloadItem) -> Void,
        exportToFiles: @escaping (DownloadItem) -> Void,
        deleteItem: @escaping (DownloadItem) -> Void
    ) {
        self.item = item
        self._shareItems = shareItems
        self.importIpaToLibrary = importIpaToLibrary
        self.exportToFiles = exportToFiles
        self.deleteItem = deleteItem
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if item.isFinished {
                Image(systemName: "doc.zipper")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            } else {
                if #available(iOS 17.0, *) {
                    Image(systemName: "arrow.down.document")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .symbolEffect(.pulse)
                } else {
                    Image(systemName: "arrow.down.document")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)
                
                Text(item.isFinished ? item.formattedFileSize : item.progressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !item.isFinished {
                ZStack {
                    Circle()
                        .trim(from: 0, to: item.progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 31, height: 31)
                        .animation(.smooth, value: item.progress)

                    Image(systemName: item.progress >= 0.75 ? "archivebox" : "square.fill")
                        .foregroundStyle(.tint)
                        .font(.footnote).bold()
                }
                .onTapGesture {
                    if item.progress <= 0.75 {
                        deleteItem(item)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isFinished {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                showingConfirmationDialog = true
            }
        }
        .confirmationDialog(
            item.title,
            isPresented: $showingConfirmationDialog,
            titleVisibility: .visible
        ) {
            fileConfirmationDialogButtons()
        }
        .contextMenu {
            fileConfirmationDialogButtons()
        }
        .swipeActions(edge: .trailing) {
            swipeActions()
        }
    }
    
    @ViewBuilder
    private func fileConfirmationDialogButtons() -> some View {
        Button {
            shareItems = [item.localPath]
            UIActivityViewController.show(activityItems: shareItems)
        } label: {
            Label(.localized("Share"), systemImage: "square.and.arrow.up")
        }
        
        Button {
            importIpaToLibrary(item)
        } label: {
            Label(.localized("Import to Library"), systemImage: "square.grid.2x2.fill")
        }
        
        Button {
            exportToFiles(item)
        } label: {
            Label(.localized("Export to Files App"), systemImage: "square.and.arrow.up.fill")
        }
        
        Button(role: .destructive) {
            deleteItem(item)
        } label: {
            Label(.localized("Delete"), systemImage: "trash")
        }
    }

    @ViewBuilder
    private func swipeActions() -> some View {
        Button(role: .destructive) {
            withAnimation {
                deleteItem(item)
            }
        } label: {
            Label(.localized("Delete"), systemImage: "trash")
        }

        Button(role: .cancel) {
            importIpaToLibrary(item)
        } label: {
            Label(.localized("Import"), systemImage: "square.grid.2x2.fill")
        }
    }
}


struct AppStoreDownloadItemRow: View {
    @ObservedObject var download: Download
//    let app: ASRepository.App

    var body: some View {
        HStack(spacing: 12) {
            if #available(iOS 17.0, *) {
                Image(systemName: rowIcon)
                    .font(.title2)
                    .foregroundColor(download.state == .failed ? .red : .accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .symbolEffect(.pulse, isActive: download.state == .downloading)
            } else {
                Image(systemName: rowIcon)
                    .font(.title2)
                    .foregroundColor(download.state == .failed ? .red : .accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(download.fileName)
                    .font(.body)
                    .lineLimit(1)

                Text(rowSubtitle)
                    .font(.caption)
                    .foregroundColor(download.state == .failed ? .red : .secondary)
            }

            Spacer()
            ZStack {
                Circle()
                    .trim(from: 0, to: download.overallProgress)
                    .stroke(download.state == .downloading ? Color.accentColor : Color.secondary,
                            style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 31, height: 31)
                    .animation(.smooth, value:  download.overallProgress)

                Image(systemName: actionIcon)
                    .foregroundStyle(.tint)
                    .font(.footnote).bold()
                }
                .onTapGesture {
                    handleTap()
                }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var rowIcon: String {
        switch download.state {
        case .paused: return "pause.circle"
        case .failed: return "exclamationmark.triangle"
        default: return download.unpackageProgress > 0 ? "doc.zipper" : "arrow.down.document"
        }
    }

    private var actionIcon: String {
        switch download.state {
        case .downloading: return download.overallProgress >= 0.75 ? "archivebox" : "square.fill"
        case .paused: return "play.fill"
        case .failed: return "arrow.clockwise"
        case .finished: return "checkmark"
        }
    }

    private var rowSubtitle: String {
        switch download.state {
        case .paused: return "已暂停 · \(download.progressText)"
        case .failed: return download.lastError ?? "下载失败"
        default: return download.progressText
        }
    }

    private func handleTap() {
        switch download.state {
        case .downloading:
            if download.overallProgress <= 0.75 {
                DownloadManager.shared.cancelDownload(download)
            }
        case .paused, .failed:
            DownloadManager.shared.resumeDownload(download)
        case .finished:
            break
        }
    }
}
