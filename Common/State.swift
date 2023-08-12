//
//  State.swift
//  Diffusion
//
//  Created by Pedro Cuenca on 17/1/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import Combine
import SwiftUI
import StableDiffusion
import CoreML

let DEFAULT_MODEL = ModelInfo.v2Base
let DEFAULT_PROMPT = "Labrador in the style of Vermeer"
let DEFAULT_MODEL_FOLDER_NAME = "hf-diffusion-models"
let DEFAULT_MODELS_FOLDER = URL.applicationSupportDirectory.appendingPathComponent(DEFAULT_MODEL_FOLDER_NAME)
let DEFAULT_COMPUTE_UNITS = ComputeUnits.cpuAndGPU

enum GenerationState {
    case startup
    case running(StableDiffusionProgress?)
    case complete(String, CGImage?, UInt32, TimeInterval?)
    case userCanceled
    case failed(Error)
}

typealias ComputeUnits = MLComputeUnits

/// Helper function to print compute units to log
func computeUnitsDescription(units: ComputeUnits) -> String {
     return {
        switch units {
        case .cpuOnly:
            return "CPU Only"
        case .cpuAndGPU:
            return "CPU and GPU"
        case .all:
            return "All"
        case .cpuAndNeuralEngine:
            return "CPU and Neural Engine"
        @unknown default:
            return "Unknown Unit"
        }
     }()
}

/// Helper function to compare compute units to attendionvariants
func convertUnitsToVariant(computeUnits: ComputeUnits?) -> AttentionVariant {
    var units: AttentionVariant {
        switch computeUnits {
        case .cpuOnly           : return .original          // Not supported yet
        case .cpuAndGPU         : return .original
        case .cpuAndNeuralEngine: return .splitEinsum
        case .all               : return .splitEinsum
        case .none:
            return .splitEinsum
        @unknown default:
            return .splitEinsum
        }
    }
    return units
}

class GenerationContext: ObservableObject {
    let scheduler = StableDiffusionScheduler.dpmSolverMultistepScheduler

    @Published var pipeline: Pipeline? = nil {
        didSet {
            if let pipeline = pipeline {
                progressSubscriber = pipeline
                    .progressPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { progress in
                        guard let progress = progress else { return }
                        self.state = .running(progress)
                    }
            }
        }
    }
    @Published var state: GenerationState = .startup
    
    @Published var positivePrompt = DEFAULT_PROMPT
    @Published var negativePrompt = ""
    
    // FIXME: Double to support the slider component
    @Published var steps = 25.0
    @Published var numImages = 1.0
    @Published var seed: UInt32 = 0
    @Published var guidanceScale = 7.5
    @Published var previews = 5.0
    @Published var disableSafety = false
    @Published var previewImage: CGImage? = nil

    @Published var computeUnits: ComputeUnits = Settings.shared.currentComputeUnits

    private var progressSubscriber: Cancellable?

    private func updatePreviewIfNeeded(_ progress: StableDiffusionProgress) {
        if previews == 0 || progress.step == 0 {
            previewImage = nil
        }

        if previews > 0, let newImage = progress.currentImages.first, newImage != nil {
            previewImage = newImage
        }
    }

    func generate() async throws -> GenerationResult {
        guard let pipeline = pipeline else { throw "No pipeline" }
        return try pipeline.generate(
            prompt: positivePrompt,
            negativePrompt: negativePrompt,
            scheduler: scheduler,
            numInferenceSteps: Int(steps),
            numPreviews: Int(previews),
            seed: seed,
            guidanceScale: Float(guidanceScale),
            disableSafety: disableSafety
        )
    }
    
    func cancelGeneration() {
        pipeline?.setCancelled()
    }
}

class Settings: ObservableObject {
    static let shared = Settings()
    
    let defaults = UserDefaults.standard
    
    @Published var isShowingImportPanel: Bool = false

    enum Keys: String {
        case model
        case computeUnits
        case safetyCheckerDisclaimer
        case modelsFolderURL
    }
    
    private init() {
        defaults.register(defaults: [
            Keys.model.rawValue: ModelInfo.v2Base.modelId,
            Keys.safetyCheckerDisclaimer.rawValue: false,
            Keys.computeUnits.rawValue: -1,  // Use default
            Keys.modelsFolderURL.rawValue: DEFAULT_MODELS_FOLDER
        ])
    }
    
    var currentModel: ModelInfo {
        set {
            defaults.set(newValue.modelId, forKey: Keys.model.rawValue)
        }
        get {
            guard let modelId = defaults.string(forKey: Keys.model.rawValue) else { return DEFAULT_MODEL }
            return ModelInfo.from(modelId: modelId) ?? DEFAULT_MODEL
        }
    }
    
    var safetyCheckerDisclaimerShown: Bool {
        set {
            defaults.set(newValue, forKey: Keys.safetyCheckerDisclaimer.rawValue)
        }
        get {
            return defaults.bool(forKey: Keys.safetyCheckerDisclaimer.rawValue)
        }
    }
    
    /// Returns the compute untils as default or units selected by the user if automatic is overridden.
    /// Set to `-1` to reset back to automatic selection for the active device
    var currentComputeUnits: ComputeUnits {
        set {
            // Any value other than the supported ones would cause `get` to return `ModelInfo.defaultComputeUnits`
            defaults.set(newValue.rawValue, forKey: Keys.computeUnits.rawValue)
        }
        get {
            let current = defaults.integer(forKey: Keys.computeUnits.rawValue)
            if !(0...3).contains(current) { return ModelInfo.defaultComputeUnits }
            if let units = ComputeUnits(rawValue: current) { return units }
            return ModelInfo.defaultComputeUnits
        }
    }

    public func applicationSupportURL() -> URL {
           let fileManager = FileManager.default
           guard let appDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
               // To ensure we don't return an optional - if the user domain application support cannot be accessed use the top level application support directory
               return URL.applicationSupportDirectory
           }

           do {
               // Create the application support directory if it doesn't exist
               try fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
               return appDirectoryURL
           } catch {
               print("Error creating application support directory: \(error)")
               return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
           }
       }
}
