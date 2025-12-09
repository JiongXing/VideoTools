//
//  VideoProcessor.swift
//  VideoTools
//
//  Created by jxing on 2025/12/9.
//

import Foundation
import Combine
import AVFoundation
import AppKit
import UniformTypeIdentifiers

class VideoProcessor: ObservableObject {
    @Published var generatedThumbnails: [NSImage] = []
    @Published var isProcessing = false
    @Published var errorMessage: String?
    
    private var asset: AVAsset?
    
    func loadVideo(from url: URL) async throws {
        await MainActor.run {
            isProcessing = true
            errorMessage = nil
        }
        
        let avAsset = AVURLAsset(url: url)
        
        // 验证视频是否可加载
        let isPlayable = try await avAsset.load(.isPlayable)
        guard isPlayable else {
            throw VideoProcessingError.videoNotPlayable
        }
        
        self.asset = avAsset
        
        await MainActor.run {
            isProcessing = false
        }
    }
    
    // 生成首帧封面
    func generateFirstFrameThumbnail() async throws {
        guard let asset = asset else {
            throw VideoProcessingError.noVideoLoaded
        }
        
        await MainActor.run {
            isProcessing = true
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        
        do {
            let cgImage = try await imageGenerator.image(at: time).image
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            await MainActor.run {
                generatedThumbnails = [nsImage]
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                isProcessing = false
                errorMessage = "生成首帧失败: \(error.localizedDescription)"
            }
            throw error
        }
    }
    
    // 随机抓取N个画面
    func generateRandomThumbnails(count: Int) async throws {
        guard let asset = asset else {
            throw VideoProcessingError.noVideoLoaded
        }
        
        await MainActor.run {
            isProcessing = true
        }
        
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        guard durationSeconds > 0 else {
            throw VideoProcessingError.invalidDuration
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        var thumbnails: [NSImage] = []
        var times: [CMTime] = []
        
        // 生成随机时间点
        for _ in 0..<count {
            let randomSeconds = Double.random(in: 0.1..<durationSeconds)
            let time = CMTime(seconds: randomSeconds, preferredTimescale: 600)
            times.append(time)
        }
        
        // 按时间排序
        times.sort { CMTimeCompare($0, $1) < 0 }
        
        // 生成图片
        for time in times {
            do {
                let cgImage = try await imageGenerator.image(at: time).image
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                thumbnails.append(nsImage)
            } catch {
                print("生成缩略图失败: \(error.localizedDescription)")
            }
        }
        
        let finalThumbnails = thumbnails
        await MainActor.run {
            generatedThumbnails = finalThumbnails
            isProcessing = false
        }
    }
    
    // 智能生成封面（首帧 + 随机几帧）
    func generateSmartThumbnail() async throws {
        guard let asset = asset else {
            throw VideoProcessingError.noVideoLoaded
        }
        
        await MainActor.run {
            isProcessing = true
        }
        
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        guard durationSeconds > 0 else {
            throw VideoProcessingError.invalidDuration
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        var thumbnails: [NSImage] = []
        
        // 首帧
        do {
            let firstFrameTime = CMTime(seconds: 0, preferredTimescale: 600)
            let cgImage = try await imageGenerator.image(at: firstFrameTime).image
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            thumbnails.append(nsImage)
        } catch {
            print("生成首帧失败: \(error.localizedDescription)")
        }
        
        // 随机3帧
        var times: [CMTime] = []
        for _ in 0..<3 {
            let randomSeconds = Double.random(in: 0.1..<durationSeconds)
            let time = CMTime(seconds: randomSeconds, preferredTimescale: 600)
            times.append(time)
        }
        times.sort { CMTimeCompare($0, $1) < 0 }
        
        for time in times {
            do {
                let cgImage = try await imageGenerator.image(at: time).image
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                thumbnails.append(nsImage)
            } catch {
                print("生成随机帧失败: \(error.localizedDescription)")
            }
        }
        
        let finalThumbnails = thumbnails
        await MainActor.run {
            generatedThumbnails = finalThumbnails
            isProcessing = false
        }
    }
    
    // 下载图片
    func saveImage(_ image: NSImage, withName name: String) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            errorMessage = "无法转换图片格式"
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = name
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try pngData.write(to: url)
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "保存失败: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    func saveAllImages() {
        for (index, image) in generatedThumbnails.enumerated() {
            let name = "thumbnail_\(index + 1).png"
            saveImage(image, withName: name)
        }
    }
}

enum VideoProcessingError: LocalizedError {
    case noVideoLoaded
    case videoNotPlayable
    case invalidDuration
    
    var errorDescription: String? {
        switch self {
        case .noVideoLoaded:
            return "未加载视频"
        case .videoNotPlayable:
            return "视频无法播放"
        case .invalidDuration:
            return "视频时长无效"
        }
    }
}

