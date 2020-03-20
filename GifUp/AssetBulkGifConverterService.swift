//
//  AssetBulkGifConverterService.swift
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


class AssetBulkGifConverterService {
    
    typealias GifConverterCompletionHandler = (URL) -> Void
    
    var builderSemaphore : DispatchSemaphore?
    var accumulatedFrames : [SampledImage] = []
    
    static var log = OSLog(subsystem: "app.nighthawk.gifUp", category: "GenerateGifWithBulkAsset")
    static var signpostID = OSSignpostID(log: AssetBulkGifConverterService.log)
    
    func buildGifFromAsset(at url: URL, forcingFramesPerSecond forcedFrameRate: CMTimeScale? = nil, completion: GifConverterCompletionHandler? = nil) throws {
        
        os_signpost(.begin, log: AssetBulkGifConverterService.log, name: "Gif Bulk Asset Conversion")
        
        let asset = AVAsset(url: url)
        
        do {
            try self.buildGifFromAsset(asset, forcingFramesPerSecond: forcedFrameRate, completion: completion)
        }
        catch let error {
            throw error
        }
        
    }
    
    func buildGifFromAsset(_ avAsset: AVAsset, forcingFramesPerSecond forcedFrameRate: CMTimeScale? = nil, completion: GifConverterCompletionHandler? = nil) throws {
        
        guard (forcedFrameRate ?? CMTimeScale.max) > 0 else {
            throw GifConversionError.unacceptableFrameRate
        }
        
        guard let assetVideoTrack = avAsset.tracks(withMediaType: .video).first else {
            throw GifConversionError.avAssetTrackTypingError
        }
        
        let runtime = avAsset.duration
        let assetFrameRate = avAsset.duration.timescale
        
        let targetFrameRate = forcedFrameRate ?? assetFrameRate
        
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
                try self.buildGifAtURL(newGifURL, from: avAsset, samplingAt: samplePoints, targetingDelayTime: timeBetweenSamplePoints)
            }
            catch let error{
                print(error)
            }
            
            actionGroup.leave()
        }
        
        actionGroup.notify(queue: .main) {
            os_signpost(.end, log: AssetBulkGifConverterService.log, name: "Gif Bulk Asset Conversion")
            completion?(newGifURL)
        }

        
    }
    
    
    func buildGifAtURL(_ targetURL: URL, from avAsset: AVAsset, samplingAt samplePoints: [CMTime], targetingDelayTime delayTimeSeconds: Double) throws {
        
        guard let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, kUTTypeGIF, samplePoints.count, nil) else {
            throw GifConversionError.failedCreateDestinationAtURL(targetURL)
        }
        
        let gifProperties = [kCGImagePropertyGIFDictionary : [kCGImagePropertyGIFLoopCount: 0]]
        
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
        
        let frameProperties = [kCGImagePropertyGIFDictionary : [kCGImagePropertyGIFDelayTime: delayTimeSeconds]]
        
        
        let assetImageGenerator = AVAssetImageGenerator(asset: avAsset)
        let tolerance = CMTime(seconds: 0.01, preferredTimescale: avAsset.duration.timescale)
        assetImageGenerator.requestedTimeToleranceAfter = tolerance
        assetImageGenerator.requestedTimeToleranceBefore = tolerance
        
        
        /// Some threading stuff has to happen here.
        
        /// First of all, to asynchronously handle making a stack of these frames, we will need to make sure we're always appending them from the same thread.
        let stackingQueue = DispatchQueue(label: "app.tweetnighthawk.GifUp.bulkDemo")
        
        /// Next, we need to make sure we know when we're done processing all the images.
        /// I'll use a semaphore and hold until we know we have all the images in place.
        /// - TODO: In this current implementation, this means if one of the frames fails capture, the semaphore will never release. This needs to be fixed if put in production.
        builderSemaphore = DispatchSemaphore(value: 0)
        
        /// `generateCGImagesASynchronously` requires an array of [NSValue] for some reason. So we gotta do that.
        let samplePointsAsValues = samplePoints.map { NSValue(time: $0) }
        
        assetImageGenerator.generateCGImagesAsynchronously(forTimes: samplePointsAsValues) { (_, image, actualTime, resultType, error) in
            
            stackingQueue.async {
                if resultType == .succeeded,
                    let image = image {
                    self.accumulatedFrames.append(SampledImage(time: actualTime, image: image))
                    if self.accumulatedFrames.count >= samplePoints.count {
                        self.builderSemaphore!.signal()
                    }
                }
            }
            
            
        }
        
        /// Wait for the frames to release.
        builderSemaphore!.wait()
        
        /// Put the frames in order and make them just the frames.
        let sortedFrames = accumulatedFrames
            .sorted { $1.time > $0.time }
            .map { $0.image }
        
        // Finally, we can build that destination with the frames we collected.
        for frame in sortedFrames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        
        if (!CGImageDestinationFinalize(destination)) {
            throw GifConversionError.failedFinalizeGIF
        }
        
    }
    
}

struct SampledImage {
    let time : CMTime
    let image: CGImage
}
