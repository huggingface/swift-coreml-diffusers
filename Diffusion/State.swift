//
//  State.swift
//  Diffusion
//
//  Created by Pedro Cuenca on 17/1/23.
//

import Combine
import SwiftUI
import StableDiffusion

let DEFAULT_MODEL = ModelInfo.v2Base

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

    private var progressSubscriber: Cancellable?

    func generate(prompt: String, steps: Int = 25, seed: UInt32? = nil) async -> (CGImage, TimeInterval)? {
        guard let pipeline = pipeline else { return nil }
        return try? pipeline.generate(prompt: prompt, scheduler: scheduler, numInferenceSteps: steps, seed: seed)
    }
}

class Settings {
    static let shared = Settings()
    
    let defaults = UserDefaults.standard
    
    enum Keys: String {
        case model
    }
    
    private init() {
        defaults.register(defaults: [
            Keys.model.rawValue: ModelInfo.v2Base.modelId
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
}
