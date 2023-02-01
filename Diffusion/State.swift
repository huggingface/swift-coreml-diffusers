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

let DEFAULT_MODEL = ModelInfo.v2Base
let DEFAULT_PROMPT = "Labrador in the style of Vermeer"

enum GenerationState {
    case startup
    case running(StableDiffusionProgress?)
    case complete(String, CGImage?, TimeInterval?)
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
    @Published var seed = -1.0
    @Published var guidanceScale = 7.5
    @Published var disableSafety = false

    private var progressSubscriber: Cancellable?

    func generate() async -> (CGImage, TimeInterval)? {
        guard let pipeline = pipeline else { return nil }
        let seed = self.seed >= 0 ? UInt32(self.seed) : nil
        return try? pipeline.generate(
            prompt: positivePrompt,
            negativePrompt: negativePrompt,
            scheduler: scheduler,
            numInferenceSteps: Int(steps),
            seed: seed,
            guidanceScale: Float(guidanceScale),
            disableSafety: disableSafety
        )
    }
}

class Settings {
    static let shared = Settings()
    
    let defaults = UserDefaults.standard
    
    enum Keys: String {
        case model
        case safetyCheckerDisclaimer
    }
    
    private init() {
        defaults.register(defaults: [
            Keys.model.rawValue: ModelInfo.v2Base.modelId,
            Keys.safetyCheckerDisclaimer.rawValue: false
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
}
