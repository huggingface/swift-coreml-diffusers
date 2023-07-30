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

enum GenerationState {
    case startup
    case running(StableDiffusionProgress?)
    case complete(String, CGImage?, UInt32, TimeInterval?)
    case userCanceled
    case failed(Error)
}

typealias ComputeUnits = MLComputeUnits

/// Schedulers compatible with StableDiffusionPipeline. This is a local implementation of the StableDiffusionScheduler enum as a String represetation to allow for compliance with NSSecureCoding.
public enum Diffusion_StableDiffusionScheduler: String {
    /// Scheduler that uses a pseudo-linear multi-step (PLMS) method
    case pndmScheduler = "pndmScheduler"
    /// Scheduler that uses a second order DPM-Solver++ algorithm
    case dpmSolverMultistepScheduler = "dpmSolverMultistepScheduler"
}

class GenerationContext: ObservableObject {
    let scheduler = Diffusion_StableDiffusionScheduler.dpmSolverMultistepScheduler

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
    
    @Published var positivePrompt = DEFAULT_PROMPT
    @Published var negativePrompt = ""
    
    // FIXME: Double to support the slider component
    @Published var steps = 25.0
    @Published var numImages = 1.0
    @Published var seed = -1.0
    @Published var guidanceScale = 7.5
    @Published var previews = 5.0
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
        let seed = self.seed >= 0 ? UInt32(self.seed) : nil
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

class Settings {
    static let shared = Settings()
    
    let defaults = UserDefaults.standard
    
    enum Keys: String {
        case model
        case safetyCheckerDisclaimer
        case computeUnits
    }
    
    private init() {
        defaults.register(defaults: [
            Keys.model.rawValue: ModelInfo.v2Base.modelId,
            Keys.safetyCheckerDisclaimer.rawValue: false,
            Keys.computeUnits.rawValue: -1      // Use default
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
