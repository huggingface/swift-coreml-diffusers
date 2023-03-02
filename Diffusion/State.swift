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
    
    @Published var computeUnits: ComputeUnits = Settings.shared.userSelectedComputeUnits ?? ModelInfo.defaultComputeUnits
    
    @Published var dataStore = HistoryStore()

    private var progressSubscriber: Cancellable?

    func generate() async throws -> GenerationResult {
        guard let pipeline = pipeline else { throw "No pipeline" }
        let seed = self.seed >= 0 ? UInt32(self.seed) : nil
        return try pipeline.generate(
            prompt: positivePrompt,
            negativePrompt: negativePrompt,
            scheduler: scheduler,
            numInferenceSteps: Int(steps),
            seed: seed,
            guidanceScale: Float(guidanceScale),
            disableSafety: disableSafety
        )
    }
    
    func cancelGeneration() {
        pipeline?.setCancelled()
    }
    
    func storeGenerationInputs(result: GenerationResult) {
        self.dataStore.historyItems.append(
            HistoryItem(
                prompt: positivePrompt,
                negativePrompt: negativePrompt,
                guidance: Float(guidanceScale),
                steps: Float(steps),
                seed: Float(result.lastSeed),
                computeUnits: self.computeUnits.rawValue,
                timing: Float(result.interval ?? -1.0 )))
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
}


struct HistoryItem: Identifiable, Codable {
    var id = UUID()
    let prompt: String
    let negativePrompt: String
    let guidance: Float
    let steps: Float
    let seed: Float
    let computeUnits: Int
    let timing: Float
}

class HistoryStore: ObservableObject {
    @Published var historyItems: [HistoryItem] {
        didSet {
            saveItems()
        }
    }
    
    init() {
        self.historyItems = HistoryStore.loadItems()
    }
    
    private static let key = "historyItems"
    
    private func saveItems() {
        print(historyItems)
        if let encoded = try? JSONEncoder().encode(historyItems) {
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }
    
    private static func loadItems() -> [HistoryItem] {
        guard let encodedItems = UserDefaults.standard.data(forKey: Self.key),
              let items = try? JSONDecoder().decode([HistoryItem].self, from: encodedItems)
        else {
            return []
        }
        return items
    }
}
