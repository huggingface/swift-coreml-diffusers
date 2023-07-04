//
//  Pipeline.swift
//  Diffusion
//
//  Created by Pedro Cuenca on December 2022.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import Foundation
import CoreML
import Combine
import StableDiffusion

typealias StableDiffusionProgress = StableDiffusionPipeline.Progress

struct GenerationResult {
    var images: [CGImage?]
    var lastSeed: UInt32
    var interval: TimeInterval?
    var userCanceled: Bool
    var itsPerSecond: Double?
}

class Pipeline {
    let pipeline: StableDiffusionPipeline
    let maxSeed: UInt32
    
    var progress: StableDiffusionProgress? = nil {
        didSet {
            progressPublisher.value = progress
        }
    }
    lazy private(set) var progressPublisher: CurrentValueSubject<StableDiffusionProgress?, Never> = CurrentValueSubject(progress)
    
    private var canceled = false

    init(_ pipeline: StableDiffusionPipeline, maxSeed: UInt32 = UInt32.max) {
        self.pipeline = pipeline
        self.maxSeed = maxSeed
    }
    
    func generate(
        prompt: String,
        negativePrompt: String = "",
        scheduler: StableDiffusionScheduler,
        numInferenceSteps stepCount: Int = 50,
        imageCount: Int,
        seed: UInt32 = 0,
        guidanceScale: Float = 7.5,
        disableSafety: Bool = false
    ) throws -> GenerationResult {
        let beginDate = Date()
        canceled = false
        let theSeed = seed > 1 ? seed : UInt32.random(in: 1...maxSeed)
        let sampleTimer = SampleTimer()
        sampleTimer.start()
        
        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = negativePrompt
        config.stepCount = stepCount
        config.imageCount = 1
        config.seed = theSeed
        config.guidanceScale = guidanceScale
        config.disableSafety = disableSafety
        config.schedulerType = scheduler
        
        let images = try pipeline.generateImages(configuration: config) { progress in
            sampleTimer.stop()
            handleProgress(progress, sampleTimer: sampleTimer)
            if progress.stepCount != progress.step {
                sampleTimer.start()
            }
            return !canceled
        }
        let interval = Date().timeIntervalSince(beginDate)
        print("Got images: \(images) in \(interval) for seed \(config.seed)")
        
        // Unwrap the images we asked for, nil means safety checker triggered
        return GenerationResult(images: images, lastSeed: theSeed, interval: interval, userCanceled: canceled, itsPerSecond: 1.0/sampleTimer.median)
    }

    func handleProgress(_ progress: StableDiffusionPipeline.Progress, sampleTimer: SampleTimer) {
        self.progress = progress
    }
        
    func setCancelled() {
        canceled = true
    }
}
