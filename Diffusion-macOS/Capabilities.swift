//
//  Capabilities.swift
//  Diffusion-macOS
//
//  Created by Pedro Cuenca on 20/2/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import Foundation

let runningOnMac = true
let deviceHas6GBOrMore = true

#if canImport(MLCompute)
import MLCompute
let _hasANE = MLCDevice.ane() != nil
#else
let _hasANE = false
#endif

final class Capabilities {
    static let hasANE = _hasANE
    
    // According to my tests this is a good proxy to estimate whether CPU+GPU
    // or CPU+NE works better. Things may become more complicated if we
    // choose all compute units.
    static var performanceCores: Int = {
        var ncores: Int32 = 0
        var bytes = MemoryLayout<Int32>.size
        
        // In M1/M2 perflevel0 refers to the performance cores and perflevel1 are the efficiency cores
        // In Intel there's only one performance level
        let result = sysctlbyname("hw.perflevel0.physicalcpu", &ncores, &bytes, nil, 0)
        guard result == 0 else { return 0 }
        return Int(ncores)
    }()
}
