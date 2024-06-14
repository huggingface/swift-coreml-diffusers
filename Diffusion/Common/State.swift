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

let DEFAULT_MODEL = ModelInfo.sd3
let DEFAULT_PROMPT = "Labrador in the style of Vermeer"

enum GenerationState {
    case startup
    case running(StableDiffusionProgress?)
    case complete(String, CGImage?, UInt32, TimeInterval?)
    case userCanceled
    case failed(Error)
}

typealias ComputeUnits = MLComputeUnits

/// Schedulers compatible with StableDiffusionPipeline. This is a local implementation of the StableDiffusionScheduler enum as a String represetation to allow for compliance with NSSecureCoding.
public enum StableDiffusionScheduler: String {
    /// Scheduler that uses a pseudo-linear multi-step (PLMS) method
    case pndmScheduler
    /// Scheduler that uses a second order DPM-Solver++ algorithm
    case dpmSolverMultistepScheduler
    /// Scheduler for rectified flow based multimodal diffusion transformer models
    case discreteFlowScheduler

    func asStableDiffusionScheduler() -> StableDiffusion.StableDiffusionScheduler {
        switch self {
        case .pndmScheduler: return StableDiffusion.StableDiffusionScheduler.pndmScheduler
        case .dpmSolverMultistepScheduler: return StableDiffusion.StableDiffusionScheduler.dpmSolverMultistepScheduler
        case .discreteFlowScheduler: return StableDiffusion.StableDiffusionScheduler.discreteFlowScheduler
        }
    }
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
                        self.updatePreviewIfNeeded(progress)
                        self.state = .running(progress)
                    }
            }
        }
    }
    @Published var state: GenerationState = .startup
    
    @Published var positivePrompt = Settings.shared.prompt
    @Published var negativePrompt = Settings.shared.negativePrompt

    // FIXME: Double to support the slider component
    @Published var steps: Double = Settings.shared.stepCount
    @Published var numImages: Double = 1.0
    @Published var seed: UInt32 = Settings.shared.seed
    @Published var guidanceScale: Double = Settings.shared.guidanceScale
    @Published var previews: Double = runningOnMac ? Settings.shared.previewCount : 0.0
    @Published var disableSafety = false
    @Published var previewImage: CGImage? = nil

    @Published var computeUnits: ComputeUnits = Settings.shared.userSelectedComputeUnits ?? ModelInfo.defaultComputeUnits

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
            seed: seed,
            numPreviews: Int(previews),
            guidanceScale: Float(guidanceScale),
            disableSafety: disableSafety
        )
    }
    
    func cancelGeneration() {
        pipeline?.setCancelled()
    }
}

class Settings {
    static let shared = Settings()
    
    let defaults = UserDefaults.standard
    
    enum Keys: String {
        case model
        case safetyCheckerDisclaimer
        case computeUnits
        case prompt
        case negativePrompt
        case guidanceScale
        case stepCount
        case previewCount
        case seed
    }

    private init() {
        defaults.register(defaults: [
            Keys.model.rawValue: ModelInfo.v2Base.modelId,
            Keys.safetyCheckerDisclaimer.rawValue: false,
            Keys.computeUnits.rawValue: -1,      // Use default
            Keys.prompt.rawValue: DEFAULT_PROMPT,
            Keys.negativePrompt.rawValue: "",
            Keys.guidanceScale.rawValue: 7.5,
            Keys.stepCount.rawValue: 25,
            Keys.previewCount.rawValue: 5,
            Keys.seed.rawValue: 0
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

    var prompt: String {
        set {
            defaults.set(newValue, forKey: Keys.prompt.rawValue)
        }
        get {
            return defaults.string(forKey: Keys.prompt.rawValue) ?? DEFAULT_PROMPT
        }
    }

    var negativePrompt: String {
        set {
            defaults.set(newValue, forKey: Keys.negativePrompt.rawValue)
        }
        get {
            return defaults.string(forKey: Keys.negativePrompt.rawValue) ?? ""
        }
    }

    var guidanceScale: Double {
        set {
            defaults.set(newValue, forKey: Keys.guidanceScale.rawValue)
        }
        get {
            return defaults.double(forKey: Keys.guidanceScale.rawValue)
        }
    }

    var stepCount: Double {
        set {
            defaults.set(newValue, forKey: Keys.stepCount.rawValue)
        }
        get {
            return defaults.double(forKey: Keys.stepCount.rawValue)
        }
    }

    var previewCount: Double {
        set {
            defaults.set(newValue, forKey: Keys.previewCount.rawValue)
        }
        get {
            return defaults.double(forKey: Keys.previewCount.rawValue)
        }
    }

    var seed: UInt32 {
        set {
            defaults.set(String(newValue), forKey: Keys.seed.rawValue)
        }
        get {
            if let seedString = defaults.string(forKey: Keys.seed.rawValue), let seedValue = UInt32(seedString) {
                return seedValue
            }
            return 0
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
    
    /// Returns the option selected by the user, if overridden
    /// `nil` means: guess best
    var userSelectedComputeUnits: ComputeUnits? {
        set {
            // Any value other than the supported ones would cause `get` to return `nil`
            defaults.set(newValue?.rawValue ?? -1, forKey: Keys.computeUnits.rawValue)
        }
        get {
            let current = defaults.integer(forKey: Keys.computeUnits.rawValue)
            guard current != -1 else { return nil }
            return ComputeUnits(rawValue: current)
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

    func tempStorageURL() -> URL {
        
        let tmpDir = applicationSupportURL().appendingPathComponent("hf-diffusion-tmp")
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: tmpDir.path) {
            do {
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create temporary directory: \(error)")
                return FileManager.default.temporaryDirectory
            }
        }
        
        return tmpDir
    }

}
