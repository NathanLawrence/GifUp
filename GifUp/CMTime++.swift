//
//  CMTime++.swift
//  Nighthawk
//
//  Created by Nathan Lawrence on 12/22/19.
//  Copyright © 2020 Team Nighthawk, LLC. All rights reserved.
//

import Foundation
import CoreGraphics
import AVFoundation

extension CMTime {
    
    var seconds: Double {
        CMTimeGetSeconds(self)
    }
    
}
