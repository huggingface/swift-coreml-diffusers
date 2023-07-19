//
//  ModelInfo.swift
//  Diffusion
//
//  Created by Pedro Cuenca on 29/12/22.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import CoreML

enum AttentionVariant: String {
    case original
    case splitEinsum
    case splitEinsumV2
}

extension AttentionVariant {
    var defaultComputeUnits: MLComputeUnits { self == .original ? .cpuAndGPU : .cpuAndNeuralEngine }
}

struct ModelInfo {
    /// Hugging Face model Id that contains .zip archives with compiled Core ML models
    let modelId: String
    
    /// Arbitrary string for presentation purposes. Something like "2.1-base"
    let modelVersion: String
    
    /// Suffix of the archive containing the ORIGINAL attention variant. Usually something like "original_compiled"
    let originalAttentionSuffix: String

    /// Suffix of the archive containing the SPLIT_EINSUM attention variant. Usually something like "split_einsum_compiled"
    let splitAttentionSuffix: String
    
    /// Suffix of the archive containing the SPLIT_EINSUM_V2 attention variant. Usually something like "split_einsum_v2_compiled"
    let splitAttentionV2Suffix: String
    
    /// Whether the archive contains the VAE Encoder (for image to image tasks). Not yet in use.
    let supportsEncoder: Bool
    
    /// Is attention v2 supported? (Ideally, we should know by looking at the repo contents)
    let supportsAttentionV2: Bool
    
    /// Are weights quantized? This is only used to decide whether to use `reduceMemory`
    let quantized: Bool
    
    //TODO: refactor all these properties
    init(modelId: String, modelVersion: String,
         originalAttentionSuffix: String = "original_compiled",
         splitAttentionSuffix: String = "split_einsum_compiled",
         splitAttentionV2Suffix: String = "split_einsum_v2_compiled",
         supportsEncoder: Bool = false,
         supportsAttentionV2: Bool = false,
         quantized: Bool = false) {
        self.modelId = modelId
        self.modelVersion = modelVersion
        self.originalAttentionSuffix = originalAttentionSuffix
        self.splitAttentionSuffix = splitAttentionSuffix
        self.splitAttentionV2Suffix = splitAttentionV2Suffix
        self.supportsEncoder = supportsEncoder
        self.supportsAttentionV2 = supportsAttentionV2
        self.quantized = quantized
    }
}

extension ModelInfo {
    //TODO: set compute units instead and derive variant from it
    static var defaultAttention: AttentionVariant {
        guard runningOnMac else { return .splitEinsum }
        #if os(macOS)
        guard Capabilities.hasANE else { return .original }
        return Capabilities.performanceCores >= 8 ? .original : .splitEinsum
        #else
        return .splitEinsum
        #endif
    }
    
    static var defaultComputeUnits: MLComputeUnits { defaultAttention.defaultComputeUnits }
    
    var bestAttention: AttentionVariant {
        if !runningOnMac && supportsAttentionV2 { return .splitEinsumV2 }
        return ModelInfo.defaultAttention
    }
    var defaultComputeUnits: MLComputeUnits { bestAttention.defaultComputeUnits }
    
    func modelURL(for variant: AttentionVariant) -> URL {
        // Pattern: https://huggingface.co/pcuenq/coreml-stable-diffusion/resolve/main/coreml-stable-diffusion-v1-5_original_compiled.zip
        let suffix: String
        switch variant {
        case .original: suffix = originalAttentionSuffix
        case .splitEinsum: suffix = splitAttentionSuffix
        case .splitEinsumV2: suffix = splitAttentionV2Suffix
        }
        let repo = modelId.split(separator: "/").last!
        return URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(repo)_\(suffix).zip")!
    }
    
    /// Best variant for the current platform.
    /// Currently using `split_einsum` for iOS and simple performance heuristics for macOS.
    var bestURL: URL { modelURL(for: bestAttention) }
    
    var reduceMemory: Bool {
        // Enable on iOS devices, except when using quantization
        if runningOnMac { return false }
        return !(quantized && deviceHas6GBOrMore)
    }
}

extension ModelInfo {
    static let v14Base = ModelInfo(
        modelId: "pcuenq/coreml-stable-diffusion-1-4",
        modelVersion: "CompVis SD 1.4"
    )

    static let v14Palettized = ModelInfo(
        modelId: "apple/coreml-stable-diffusion-1-4-palettized",
        modelVersion: "CompVis SD 1.4 [6 bit]",
        supportsEncoder: true,
        supportsAttentionV2: true,
        quantized: true
    )

    static let v15Base = ModelInfo(
        modelId: "pcuenq/coreml-stable-diffusion-v1-5",
        modelVersion: "RunwayML SD 1.5"
    )
    
    static let v15Palettized = ModelInfo(
        modelId: "apple/coreml-stable-diffusion-v1-5-palettized",
        modelVersion: "RunwayML SD 1.5 [6 bit]",
        supportsEncoder: true,
        supportsAttentionV2: true,
        quantized: true
    )
    
    static let v2Base = ModelInfo(
        modelId: "pcuenq/coreml-stable-diffusion-2-base",
        modelVersion: "StabilityAI SD 2.0",
        supportsEncoder: true
    )
    
    static let v2Palettized = ModelInfo(
        modelId: "apple/coreml-stable-diffusion-2-base-palettized",
        modelVersion: "StabilityAI SD 2.0 [6 bit]",
        supportsEncoder: true,
        supportsAttentionV2: true,
        quantized: true
    )

    static let v21Base = ModelInfo(
        modelId: "pcuenq/coreml-stable-diffusion-2-1-base",
        modelVersion: "StabilityAI SD 2.1",
        supportsEncoder: true
    )
    
    static let v21Palettized = ModelInfo(
        modelId: "apple/coreml-stable-diffusion-2-1-base-palettized",
        modelVersion: "StabilityAI SD 2.1 [6 bit]",
        supportsEncoder: true,
        supportsAttentionV2: true,
        quantized: true
    )
        
    static let ofaSmall = ModelInfo(
        modelId: "pcuenq/coreml-small-stable-diffusion-v0",
        modelVersion: "OFA-Sys/small-stable-diffusion-v0"
    )
    
    static let MODELS: [ModelInfo] = {
        if deviceSupportsQuantization {
            return [
                ModelInfo.v14Base,
                ModelInfo.v14Palettized,
                ModelInfo.v15Base,
                ModelInfo.v15Palettized,
                ModelInfo.v2Base,
                ModelInfo.v2Palettized,
                ModelInfo.v21Base,
                ModelInfo.v21Palettized,
                ModelInfo.ofaSmall
            ]
        } else {
            return [
                ModelInfo.v14Base,
                ModelInfo.v15Base,
                ModelInfo.v2Base,
                ModelInfo.v21Base,
                ModelInfo.ofaSmall
            ]
        }
    }()
    
    static func from(modelVersion: String) -> ModelInfo? {
        ModelInfo.MODELS.first(where: {$0.modelVersion == modelVersion})
    }
    
    static func from(modelId: String) -> ModelInfo? {
        ModelInfo.MODELS.first(where: {$0.modelId == modelId})
    }
}

extension ModelInfo : Equatable {
    static func ==(lhs: ModelInfo, rhs: ModelInfo) -> Bool { lhs.modelId == rhs.modelId }
}
