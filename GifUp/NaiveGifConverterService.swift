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


class NaiveGifConverterService {
    
    static var log = OSLog(subsystem: "app.nighthawk.gifUp", category: "GenerateGifNaively")
    static var signpostID = OSSignpostID(log: NaiveGifConverterService.log)
    
    typealias GifConverterCompletionHandler = (URL) -> Void
    
    static func buildGifFromAsset(at url: URL, forcingFramesPerSecond forcedFrameRate: CMTimeScale? = nil, completion: GifConverterCompletionHandler? = nil) throws {
        
        os_signpost(.begin, log: NaiveGifConverterService.log, name: "Naive Gif Conversion")
        
        let asset = AVAsset(url: url)
        
        do {
            try NaiveGifConverterService.buildGifFromAsset(asset, forcingFramesPerSecond: forcedFrameRate, completion: completion)
        }
        catch let error {
            throw error
        }
        
    }
    
    static func buildGifFromAsset(_ avAsset: AVAsset, forcingFramesPerSecond forcedFrameRate: CMTimeScale? = nil, completion: GifConverterCompletionHandler? = nil) throws {
        
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
                try NaiveGifConverterService.buildGifAtURL(newGifURL, from: avAsset, samplingAt: samplePoints, targetingDelayTime: timeBetweenSamplePoints)
            }
            catch let error{
                print(error)
            }
            
            actionGroup.leave()
        }
        
        actionGroup.notify(queue: .main) {
            os_signpost(.end, log: NaiveGifConverterService.log, name: "Naive Gif Conversion")
            completion?(newGifURL)
        }
        
    }
    
    
    static func buildGifAtURL(_ targetURL: URL, from avAsset: AVAsset, samplingAt samplePoints: [CMTime], targetingDelayTime delayTimeSeconds: Double) throws {
        
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
        
        for samplePoint in samplePoints {
            do {
                let image = try assetImageGenerator.copyCGImage(at: samplePoint, actualTime: nil)
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            }
            catch let err {
                throw err
            }
        }
        
        if (!CGImageDestinationFinalize(destination)) {
            throw GifConversionError.failedFinalizeGIF
        }

    }
    
}

