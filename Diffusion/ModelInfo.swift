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
    
    /// Whether the archive contains the VAE Encoder (for image to image tasks). Not yet in use.
    let supportsEncoder: Bool
        
    init(modelId: String, modelVersion: String, originalAttentionSuffix: String = "original_compiled", splitAttentionSuffix: String = "split_einsum_compiled", supportsEncoder: Bool = false) {
        self.modelId = modelId
        self.modelVersion = modelVersion
        self.originalAttentionSuffix = originalAttentionSuffix
        self.splitAttentionSuffix = splitAttentionSuffix
        self.supportsEncoder = supportsEncoder
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
    
    var bestAttention: AttentionVariant { ModelInfo.defaultAttention }
    var defaultComputeUnits: MLComputeUnits { bestAttention.defaultComputeUnits }
    
    func modelURL(for variant: AttentionVariant) -> URL {
        // Pattern: https://huggingface.co/pcuenq/coreml-stable-diffusion/resolve/main/coreml-stable-diffusion-v1-5_original_compiled.zip
        let suffix: String
        switch variant {
        case .original: suffix = originalAttentionSuffix
        case .splitEinsum: suffix = splitAttentionSuffix
        }
        let repo = modelId.split(separator: "/").last!
        return URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(repo)_\(suffix).zip")!
    }
    
    /// Best variant for the current platform.
    /// Currently using `split_einsum` for iOS and simple performance heuristics for macOS.
    var bestURL: URL { modelURL(for: bestAttention) }
        
    var reduceMemory: Bool {
        return !runningOnMac
    }
}

extension ModelInfo {
    // TODO: repo does not exist yet
    static let v14Base = ModelInfo(
        modelId: "pcuenq/coreml-stable-diffusion-1-4",
        modelVersion: "CompVis/stable-diffusion-v1-4"
    )

    static let v15Base = ModelInfo(
        modelId: "pcuenq/coreml-stable-diffusion-v1-5",
        modelVersion: "runwayml/stable-diffusion-v1-5"
    )
    
    static let v2Base = ModelInfo(
        modelId: "pcuenq/coreml-stable-diffusion-2-base",
        modelVersion: "stabilityai/stable-diffusion-2-base"
    )

    static let v21Base = ModelInfo(
        modelId: "pcuenq/coreml-stable-diffusion-2-1-base",
        modelVersion: "stabilityai/stable-diffusion-2-1-base",
        supportsEncoder: true
    )

    static let ojV2Base = ModelInfo(
        modelId: "dcolish/coreml-openjourney-v2",
        modelVersion: "prompthero/openjourney-v2"
    )
    
    static let ofaSmall = ModelInfo(
        modelId: "pcuenq/coreml-small-stable-diffusion-v0",
        modelVersion: "OFA-Sys/small-stable-diffusion-v0"
    )

    static let MODELS = [
        ModelInfo.v14Base,
        ModelInfo.v15Base,
        ModelInfo.v2Base,
        ModelInfo.v21Base,
        ModelInfo.ofaSmall,
        ModelInfo.ojV2Base
    ]
    
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
