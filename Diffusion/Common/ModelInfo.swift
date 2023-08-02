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

/// Track if the model is downloaded and on the filesystem, ready for use.
enum ModelReadinessState {
    case unknown
    case downloading
    case downloaded
    case uncompressing
    case ready
    case failed
}

class ModelReadiness: ObservableObject {
    let modelInfo: ModelInfo
    @Published var state: ModelReadinessState

    init(modelInfo: ModelInfo, state: ModelReadinessState) {
        self.modelInfo = modelInfo
        self.state = state
    }
}

struct ModelInfo {
    /// Hugging Face model Id that contains .zip archives with compiled Core ML models
    let modelId: String

    /// Arbitrary string for presentation purposes. Something like "2.1-base"
    let modelVersion: String

    /// Which attention variant is this model associated with?
    let variant: AttentionVariant

    /// Is this a user added model or a built-in?
    let builtin: Bool

    /// Decomposted version of `fileSystemFileName` to show in the UI
    var humanReadableFileName: String

    /// The name of the model's parent folder as it sits in the user selected models folder
    var fileSystemFileName: String

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

    /// Whether this is a Stable Diffusion XL model
    // TODO: retrieve from remote config
    let isXL: Bool

    //TODO: refactor all these properties
    init(modelId: String,
         modelVersion: String,
         variant: AttentionVariant,
         builtin: Bool,
         humanReadableFileName: String,
         fileSystemFileName: String,
         originalAttentionSuffix: String = "original_compiled",
         splitAttentionSuffix: String = "split_einsum_compiled",
         splitAttentionV2Suffix: String = "split_einsum_v2_compiled",
         supportsEncoder: Bool = false,
         supportsAttentionV2: Bool = false,
         quantized: Bool = false,
         isXL: Bool = false) {
        self.modelId = modelId
        self.variant = variant
        self.builtin = builtin
        self.modelVersion = modelVersion
        self.humanReadableFileName = humanReadableFileName
        self.originalAttentionSuffix = originalAttentionSuffix
        self.splitAttentionSuffix = splitAttentionSuffix
        self.splitAttentionV2Suffix = splitAttentionV2Suffix
        self.supportsEncoder = supportsEncoder
        self.supportsAttentionV2 = supportsAttentionV2
        self.quantized = quantized
        self.fileSystemFileName = fileSystemFileName
        self.isXL = isXL
        if builtin {
            self.fileSystemFileName = fileSystemFileName + "_" + fileSuffix()
        }
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

    static let xl = ModelInfo(
        modelId: "apple/coreml-stable-diffusion-xl-base",
        modelVersion: "Stable Diffusion XL base",
        variant: AttentionVariant.original,
        builtin: true,
        humanReadableFileName: "CoreML Stable Diffusion XL Base",
        fileSystemFileName: "coreml-stable-diffusion-XL",
        supportsEncoder: true,
        isXL: true
    )

    static let xlmbp = ModelInfo(
        modelId: "apple/coreml-stable-diffusion-mixed-bit-palettization",
        modelVersion: "Stable Diffusion XL base [4.5 bit]",
        variant: AttentionVariant.splitEinsumV2,
        builtin: true,
        humanReadableFileName: "CoreML Stable Diffusion XL Base",
        fileSystemFileName: "coreml-stable-diffusion-XL",
        supportsEncoder: true,
        quantized: true,
        isXL: true
    )

    static let v14Base = ModelInfo(modelId: "pcuenq/coreml-stable-diffusion-1-4",
        modelVersion: "CompVis SD 1.4",
        variant: AttentionVariant.original,
        builtin: true,
        humanReadableFileName: "CoreML Stable Diffusion v1.4",
        fileSystemFileName: "coreml-stable-diffusion-1-4")

    static let v14Palettized = ModelInfo(modelId: "apple/coreml-stable-diffusion-1-4-palettized",
        modelVersion: "CompVis SD 1.4 [6 bit]",
        variant: AttentionVariant.splitEinsumV2,
        builtin: true,
        humanReadableFileName: "CoreML Stable Diffusion v1.4 Palettized",
        fileSystemFileName: "coreml-stable-diffusion-1-4-palettized",
        supportsEncoder: true,
        supportsAttentionV2: true,
        quantized: true)

    static let v15Base = ModelInfo(modelId: "pcuenq/coreml-stable-diffusion-v1-5",
        modelVersion: "RunwayML SD 1.5",
        variant: AttentionVariant.original,
        builtin: true,
        humanReadableFileName: "CoreML Stable Diffusion v1.5",
        fileSystemFileName: "coreml-stable-diffusion-v1-5")

    static let v15Palettized = ModelInfo(modelId: "apple/coreml-stable-diffusion-v1-5-palettized",
        modelVersion: "RunwayML SD 1.5 [6 bit]",
        variant: AttentionVariant.splitEinsumV2,
        builtin: true,
        humanReadableFileName: "CoreML Stable Diffusion v1.5 Palettized",
        fileSystemFileName: "coreml-stable-diffusion-v1-5-palettized",
        supportsEncoder: true,
        supportsAttentionV2: true,
        quantized: true)

    static let v2Base = ModelInfo(modelId: "pcuenq/coreml-stable-diffusion-2-base",
        modelVersion: "StabilityAI SD 2.0",
        variant: AttentionVariant.original,
        builtin: true,
        humanReadableFileName: "CoreML Stable Diffusion v2",
        fileSystemFileName: "coreml-stable-diffusion-2-base",
        supportsEncoder: true)

    static let v2Palettized = ModelInfo(modelId: "apple/coreml-stable-diffusion-2-base-palettized",
        modelVersion: "StabilityAI SD 2.0 [6 bit]",
        variant: AttentionVariant.splitEinsumV2,
        builtin: true,
        humanReadableFileName: "CoreML Stable Diffusion v2 Palettized",
        fileSystemFileName: "coreml-stable-diffusion-2-base-palettized",
        supportsEncoder: true,
        supportsAttentionV2: true,
        quantized: true)

    static let v21Base = ModelInfo(modelId: "pcuenq/coreml-stable-diffusion-2-1-base",
        modelVersion: "StabilityAI SD 2.1",
        variant: AttentionVariant.original,
        builtin: true,
        humanReadableFileName: "CoreML Stable Diffusion v2.1",
        fileSystemFileName: "coreml-stable-diffusion-2-1-base",
        supportsEncoder: true)

    static let v21Palettized = ModelInfo(modelId: "apple/coreml-stable-diffusion-2-1-base-palettized",
        modelVersion: "StabilityAI SD 2.1 [6 bit]",
        variant: AttentionVariant.splitEinsumV2,
        builtin: true,
        humanReadableFileName: "CoreML Stable Diffusion v2.1 Palettized",
        fileSystemFileName: "coreml-stable-diffusion-2-1-base-palettized",
        supportsEncoder: true,
        supportsAttentionV2: true,
        quantized: true)

       static let BUILTIN_MODELS: [ModelInfo] = {
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
                   ModelInfo.xl,
                   ModelInfo.xlmbp
               ]
           } else {
               return [
                   ModelInfo.v14Base,
                   ModelInfo.v15Base,
                   ModelInfo.v2Base,
                   ModelInfo.v21Base
               ]
           }
       }()

       static func from(modelVersion: String) -> ModelInfo? {
           ModelInfo.BUILTIN_MODELS.first(where: {$0.modelVersion == modelVersion})
       }

       static func from(modelId: String) -> ModelInfo? {
           ModelInfo.BUILTIN_MODELS.first(where: {$0.modelId == modelId})
       }
   }

extension ModelInfo : Equatable {
    static func ==(lhs: ModelInfo, rhs: ModelInfo) -> Bool { lhs.modelId == rhs.modelId }
}

extension ModelInfo {
    func fileSuffix() -> String {
        let suffix: String
        switch variant {
        case .original: suffix = originalAttentionSuffix
        case .splitEinsum: suffix = splitAttentionSuffix
        case .splitEinsumV2: suffix = splitAttentionV2Suffix
        }
        return suffix
    }
}
