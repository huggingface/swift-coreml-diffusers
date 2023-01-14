//
//  ModelInfo.swift
//  Diffusion
//
//  Created by Pedro Cuenca on 29/12/22.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import CoreML

struct ModelInfo {
    /// Hugging Face model Id that contains .zip archives with compiled Core ML models
    let modelId: String
    
    /// Arbitrary string for presentation purposes. Something like "2.1-base"
    let modelVersion: String
    
    /// Suffix of the archive containing the ORIGINAL attention variant. Usually something like "original_compiled"
    let originalAttentionSuffix: String

    /// Suffix of the archive containing the SPLIT_EINSUM attention variant. Usually something like "split_einsum_compiled"
    let splitAttentionName: String
    
    /// Whether the archive contains the VAE Encoder (for image to image tasks). Not yet in use.
    let supportsEncoder: Bool
        
    init(modelId: String, modelVersion: String, originalAttentionSuffix: String = "original_compiled", splitAttentionName: String = "split_einsum_compiled", supportsEncoder: Bool = false) {
        self.modelId = modelId
        self.modelVersion = modelVersion
        self.originalAttentionSuffix = originalAttentionSuffix
        self.splitAttentionName = splitAttentionName
        self.supportsEncoder = supportsEncoder
    }
}

extension ModelInfo {
    /// Best variant for the current platform.
    /// Currently using `split_einsum` for iOS and `original` for macOS, but could vary depending on model.
    var bestURL: URL {
        // Pattern: https://huggingface.co/pcuenq/coreml-stable-diffusion/resolve/main/coreml-stable-diffusion-v1-5_original_compiled.zip
        let suffix = runningOnMac ? originalAttentionSuffix : splitAttentionName
        let repo = modelId.split(separator: "/").last!
        return URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(repo)_\(suffix).zip")!
    }
    
    /// Best units for current platform.
    /// Currently using `cpuAndNeuralEngine` for iOS and `cpuAndGPU` for macOS, but could vary depending on model.
    /// .all works for v1.4, but not for v1.5.
    // TODO: measure performance on different devices.
    var bestComputeUnits: MLComputeUnits {
        return runningOnMac ? .cpuAndGPU : .cpuAndNeuralEngine
    }
    
    var reduceMemory: Bool {
        return !runningOnMac
    }
}

extension ModelInfo {
    // TODO: repo does not exist yet
    static let v14Base = ModelInfo(
        modelId: "pcuenq/coreml-stable-diffusion-v1-4",
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
    
    static let MODELS = [
        ModelInfo.v14Base,
        ModelInfo.v15Base,
        ModelInfo.v2Base,
        ModelInfo.v21Base
    ]
}
