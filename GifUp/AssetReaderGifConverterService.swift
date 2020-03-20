//
//  GifConverterService.swift
//  GifUp
//
//  Created by Nathan Lawrence on 3/19/20.
//  Copyright © 2020 Team Nighthawk, LLC. All rights reserved.
//

import Foundation
import AVFoundation
import CoreGraphics
import Dispatch
import CoreServices
import MobileCoreServices
import os


class AssetReaderGifConverterService {
    
    static var log = OSLog(subsystem: "app.nighthawk.gifUp", category: "GenerateGifFromAssetReader")
    static var signpostID = OSSignpostID(log: AssetReaderGifConverterService.log)
    
    typealias GifConverterCompletionHandler = (URL) -> Void
    
    static func buildGifFromAsset(at url: URL, completion: GifConverterCompletionHandler? = nil) throws {
        
        os_signpost(.begin, log: AssetReaderGifConverterService.log, name: "AR Gif Conversion")
        
        let asset = AVAsset(url: url)
        
        do {
            try AssetReaderGifConverterService.buildGifFromAsset(asset, completion: completion)
        }
        catch let error {
            throw error
        }
        
    }
    
    static func buildGifFromAsset(_ avAsset: AVAsset, completion: GifConverterCompletionHandler? = nil) throws {
        
        
        let runtime = avAsset.duration
        let assetFrameRate = avAsset.duration.timescale
        
        let targetFrameRate = assetFrameRate
        
        // It may look like we're doing a lot of redundant back-and-forth here, but the processing to do this is very cheap, and it saves us a ton of maintenance on near-redundant processes for converting between native and non-native frame rates for the same video.
        let targetTotalFrames = runtime.seconds * Double(targetFrameRate)
        let timeBetweenSamplePoints = runtime.seconds/targetTotalFrames
        
        
        // Time for some good old fashioned loop assembly.
        // Is there a better way to do this? Almost certainly.
        // Will I be doing that today? Almost certainly not.
        var samplePoints : [CMTime] = []
        var nextSamplePointInSeconds : Double = 0
        repeat {
            samplePoints.append(CMTime(seconds: nextSamplePointInSeconds, preferredTimescale: assetFrameRate))
            nextSamplePointInSeconds += timeBetweenSamplePoints
        } while nextSamplePointInSeconds < runtime.seconds
        
        
        let temporaryDirectory = NSTemporaryDirectory()
        let newGifURL = URL(fileURLWithPath: "\(temporaryDirectory)\(UUID()).gif")
        
        let actionGroup = DispatchGroup()
        
        actionGroup.enter()
        
        DispatchQueue.global(qos: .default).async {
            do {
                try AssetReaderGifConverterService.buildGifAtURL(newGifURL, from: avAsset, samplingAt: samplePoints, targetingDelayTime: timeBetweenSamplePoints)
            }
            catch let error{
                print(error)
            }
            
            actionGroup.leave()
        }
        
        actionGroup.notify(queue: .main) {
            os_signpost(.end, log: AssetReaderGifConverterService.log, name: "AR Gif Conversion")
            completion?(newGifURL)
        }
        
    }
    
    static func cgImageFromSampleBuffer(_ buffer: CMSampleBuffer) -> CGImage? {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        
        
        let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        let image = context?.makeImage()
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        return image
    }
    
    
    static func buildGifAtURL(_ targetURL: URL, from avAsset: AVAsset, samplingAt samplePoints: [CMTime], targetingDelayTime delayTimeSeconds: Double) throws {
        
        guard let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, kUTTypeGIF, samplePoints.count, nil) else {
            throw GifConversionError.failedCreateDestinationAtURL(targetURL)
        }
        
        let gifProperties = [kCGImagePropertyGIFDictionary : [kCGImagePropertyGIFLoopCount: 0]]
        
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
        
        let frameProperties = [kCGImagePropertyGIFDictionary : [kCGImagePropertyGIFDelayTime: delayTimeSeconds]]
        
        
        guard let assetReader = try? AVAssetReader(asset: avAsset),
            let videoTrack = avAsset.tracks(withMediaType: .video).first else {
                throw GifConversionError.failedCreateAssetReader
        }
        
        let assetReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32ARGB])
        
        assetReader.add(assetReaderOutput)
        assetReader.startReading()
        
        while (assetReader.status == .reading) {
            
            guard let buffer = assetReaderOutput.copyNextSampleBuffer() else {
                break
            }
            guard let image = AssetReaderGifConverterService.cgImageFromSampleBuffer(buffer) else {
                    continue
            }
            
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            
        }
        
        if (!CGImageDestinationFinalize(destination)) {
            throw GifConversionError.failedFinalizeGIF
        }
        
    }
    
}

