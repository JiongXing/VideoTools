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
    @Published var compressedThumbnails: [NSImage] = []
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var compressionQuality: Double = 0.8
    
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
        let imagesToSave = compressedThumbnails.isEmpty ? generatedThumbnails : compressedThumbnails
        for (index, image) in imagesToSave.enumerated() {
            let name = "thumbnail_\(index + 1).png"
            saveImage(image, withName: name)
        }
    }
    
    // 压缩单个图片（实例方法，调用静态方法）
    func compressImage(_ image: NSImage, quality: Double) -> NSImage? {
        return VideoProcessor.compressImageStatic(image, quality: quality)
    }
    
    // 压缩所有生成的封面
    func compressAllThumbnails() async {
        await MainActor.run {
            isProcessing = true
            errorMessage = nil
        }
        
        let thumbnails = await MainActor.run {
            Array(generatedThumbnails)
        }
        let quality = await MainActor.run {
            compressionQuality
        }
        
        // 在后台线程进行压缩处理
        let compressed: [NSImage] = await Task.detached { [thumbnails, quality] in
            var result: [NSImage] = []
            for image in thumbnails {
                // 创建压缩函数，不捕获 self
                if let compressedImage = VideoProcessor.compressImageStatic(image, quality: quality) {
                    result.append(compressedImage)
                } else {
                    // 如果压缩失败，使用原图
                    result.append(image)
                }
            }
            return result
        }.value
        
        await MainActor.run {
            compressedThumbnails = compressed
            isProcessing = false
        }
    }
    
    // 静态压缩方法，用于在后台线程调用
    private static func compressImageStatic(_ image: NSImage, quality: Double) -> NSImage? {
        guard let tiffData = image.tiffRepresentation,
              NSBitmapImageRep(data: tiffData) != nil else {
            return nil
        }
        
        // 计算压缩后的尺寸（保持宽高比，最大宽度或高度为 1920）
        let maxDimension: CGFloat = 1920
        var newSize = image.size
        
        if newSize.width > maxDimension || newSize.height > maxDimension {
            let aspectRatio = newSize.width / newSize.height
            if newSize.width > newSize.height {
                newSize = NSSize(width: maxDimension, height: maxDimension / aspectRatio)
            } else {
                newSize = NSSize(width: maxDimension * aspectRatio, height: maxDimension)
            }
        }
        
        // 调整图片尺寸
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        resizedImage.unlockFocus()
        
        // 转换为 JPEG 格式进行压缩
        guard let resizedTiff = resizedImage.tiffRepresentation,
              let resizedBitmap = NSBitmapImageRep(data: resizedTiff),
              let jpegData = resizedBitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            return resizedImage
        }
        
        // 将压缩后的 JPEG 数据转换回 NSImage
        guard let compressedImage = NSImage(data: jpegData) else {
            return resizedImage
        }
        
        return compressedImage
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

