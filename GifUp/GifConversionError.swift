//
//  GifConversionError.swift
//  GifUp
//
//  Created by Nathan Lawrence on 3/20/20.
//  Copyright © 2020 Team Nighthawk, LLC. All rights reserved.
//

import Foundation

enum GifConversionError : Error {
    case unacceptableFrameRate
    case avAssetTrackTypingError
    case failedCreateDestinationAtURL(URL)
    case failedFinalizeGIF
    case failedCreateAssetReader
}
