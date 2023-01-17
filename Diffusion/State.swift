//
//  State.swift
//  Diffusion
//
//  Created by Pedro Cuenca on 17/1/23.
//

import SwiftUI

let DEFAULT_MODEL = ModelInfo.v2Base

class DiffusionGlobals: ObservableObject {
    @Published var pipeline: Pipeline? = nil
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
