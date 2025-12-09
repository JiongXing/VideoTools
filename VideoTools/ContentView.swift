//
//  ContentView.swift
//  VideoTools
//
//  Created by jxing on 2025/12/9.
//

import SwiftUI
import AVKit
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var videoProcessor = VideoProcessor()
    @State private var randomFrameCount: Int = 5
    @State private var currentVideoURL: URL?
    @State private var loadErrorMessage: String?
    @State private var isDragging = false
    @State private var useCompressed: Bool = false
    
    // 根据是否使用压缩版本来决定显示的缩略图
    private var displayThumbnails: [NSImage] {
        if useCompressed && !videoProcessor.compressedThumbnails.isEmpty {
            return videoProcessor.compressedThumbnails
        }
        return videoProcessor.generatedThumbnails
    }
    
    var body: some View {
        HSplitView {
            // 左侧：视频播放区域
            VStack(spacing: 16) {
                // 文件选择按钮
                HStack {
                    Button("选择视频文件") {
                        selectVideoFile()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if let url = currentVideoURL {
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                
                // 加载错误提示
                if let error = loadErrorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                // 视频播放器（支持拖拽）
                ZStack {
                    if let url = currentVideoURL {
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .cornerRadius(8)
                            .padding()
                            .overlay(
                                // 拖拽覆盖层提示
                                Group {
                                    if isDragging {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue.opacity(0.3))
                                            .overlay(
                                                VStack(spacing: 16) {
                                                    Image(systemName: "arrow.down.circle.fill")
                                                        .font(.system(size: 48))
                                                        .foregroundColor(.blue)
                                                    Text("松开以替换视频")
                                                        .foregroundColor(.primary)
                                                        .fontWeight(.semibold)
                                                }
                                            )
                                            .padding()
                                    }
                                }
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isDragging ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(
                                VStack(spacing: 16) {
                                    Image(systemName: isDragging ? "arrow.down.circle.fill" : "video.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(isDragging ? .blue : .secondary)
                                    Text(isDragging ? "松开以加载视频" : "拖拽视频文件到这里\n或点击上方按钮选择文件")
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            )
                            .padding()
                    }
                }
                .onDrop(of: [.movie, .video, .fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers: providers)
                }
            }
            .frame(minWidth: 400)
            
            // 右侧：封面生成区域
            VStack(spacing: 20) {
                Text("视频封面生成")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                // 功能按钮区域
                VStack(spacing: 12) {
                    Button("智能生成封面") {
                        Task {
                            await generateSmartThumbnail()
                            useCompressed = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(currentVideoURL == nil || videoProcessor.isProcessing)
                    
                    Button("截取首帧") {
                        Task {
                            await generateFirstFrame()
                            useCompressed = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(currentVideoURL == nil || videoProcessor.isProcessing)
                    
                    HStack {
                        Text("随机抓取")
                        Stepper("", value: $randomFrameCount, in: 1...20)
                        Text("\(randomFrameCount)个画面")
                    }
                    
                    Button("生成随机封面") {
                        Task {
                            await generateRandomFrames()
                            useCompressed = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(currentVideoURL == nil || videoProcessor.isProcessing)
                    
                    if !videoProcessor.generatedThumbnails.isEmpty {
                        // 压缩质量设置
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("压缩质量")
                                Spacer()
                                Text("\(Int(videoProcessor.compressionQuality * 100))%")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $videoProcessor.compressionQuality, in: 0.1...1.0, step: 0.1)
                        }
                        
                        Button("压缩所有封面") {
                            Task {
                                await videoProcessor.compressAllThumbnails()
                                useCompressed = true
                            }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(videoProcessor.isProcessing)
                        
                        Button("下载所有封面") {
                            videoProcessor.saveAllImages()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                
                // 处理状态
                if videoProcessor.isProcessing {
                    ProgressView("正在处理...")
                        .padding()
                }
                
                if let error = videoProcessor.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
                
                // 生成的封面展示
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                        ForEach(Array(displayThumbnails.enumerated()), id: \.offset) { index, image in
                            VStack {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 150, height: 150)
                                    .cornerRadius(8)
                                    .shadow(radius: 4)
                                
                                if useCompressed && !videoProcessor.compressedThumbnails.isEmpty {
                                    Text("已压缩")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Button("下载") {
                                    videoProcessor.saveImage(image, withName: "thumbnail_\(index + 1).png")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .frame(minWidth: 350)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    private func selectVideoFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
            .avi,
            .video
        ]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                loadVideo(from: url)
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        // 处理视频文件类型
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { item, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.loadErrorMessage = "加载文件失败: \(error.localizedDescription)"
                        return
                    }
                    
                    if let url = item as? URL {
                        self.loadVideo(from: url)
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        self.loadVideo(from: url)
                    }
                }
            }
            return true
        }
        
        // 处理文件URL类型
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.loadErrorMessage = "加载文件失败: \(error.localizedDescription)"
                        return
                    }
                    
                    var url: URL?
                    
                    if let urlItem = item as? URL {
                        url = urlItem
                    } else if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let string = item as? String {
                        url = URL(fileURLWithPath: string)
                    }
                    
                    if let fileURL = url {
                        // 检查文件扩展名是否为视频格式
                        let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "flv", "wmv", "webm", "mpg", "mpeg", "3gp"]
                        let fileExtension = fileURL.pathExtension.lowercased()
                        
                        if videoExtensions.contains(fileExtension) || fileExtension.isEmpty {
                            // 如果扩展名为空，尝试检查文件类型
                            self.loadVideo(from: fileURL)
                        } else {
                            self.loadErrorMessage = "不支持的文件格式: \(fileExtension)"
                        }
                    }
                }
            }
            return true
        }
        
        return false
    }
    
    private func loadVideo(from url: URL) {
        loadErrorMessage = nil
        currentVideoURL = url
        
        Task {
            do {
                try await videoProcessor.loadVideo(from: url)
            } catch {
                await MainActor.run {
                    loadErrorMessage = "加载视频失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func generateSmartThumbnail() async {
        guard let url = currentVideoURL else { return }
        
        do {
            try await videoProcessor.loadVideo(from: url)
            try await videoProcessor.generateSmartThumbnail()
        } catch {
            await MainActor.run {
                videoProcessor.errorMessage = "生成智能封面失败: \(error.localizedDescription)"
            }
        }
    }
    
    private func generateFirstFrame() async {
        guard let url = currentVideoURL else { return }
        
        do {
            try await videoProcessor.loadVideo(from: url)
            try await videoProcessor.generateFirstFrameThumbnail()
        } catch {
            await MainActor.run {
                videoProcessor.errorMessage = "生成首帧失败: \(error.localizedDescription)"
            }
        }
    }
    
    private func generateRandomFrames() async {
        guard let url = currentVideoURL else { return }
        
        do {
            try await videoProcessor.loadVideo(from: url)
            try await videoProcessor.generateRandomThumbnails(count: randomFrameCount)
        } catch {
            await MainActor.run {
                videoProcessor.errorMessage = "生成随机封面失败: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ContentView()
}
