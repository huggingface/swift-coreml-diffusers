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

struct StableDiffusionProgress {
    var progress: StableDiffusionPipeline.Progress

    var step: Int { progress.step }
    var stepCount: Int { progress.stepCount }

    var currentImages: [CGImage?]

    init(progress: StableDiffusionPipeline.Progress, previewIndices: [Bool]) {
        self.progress = progress
        self.currentImages = [nil]

        // Since currentImages is a computed property, only access the preview image if necessary
        if progress.step < previewIndices.count, previewIndices[progress.step] {
            self.currentImages = progress.currentImages
        }
    }
}

struct GenerationResult {
    var image: CGImage?
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
        scheduler: Diffusion_StableDiffusionScheduler,
        numInferenceSteps stepCount: Int = 50,
        numPreviews previewCount: Int = 5,
        seed: UInt32? = nil,
        guidanceScale: Float = 7.5,
        disableSafety: Bool = false
    ) throws -> GenerationResult {
        let beginDate = Date()
        canceled = false

        let theSeed = seed ?? UInt32.random(in: 0...maxSeed)
        let sampleTimer = SampleTimer()
        sampleTimer.start()
        
        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = negativePrompt
        config.stepCount = stepCount
        config.seed = theSeed
        config.guidanceScale = guidanceScale
        config.disableSafety = disableSafety
        if (scheduler == .dpmSolverMultistepScheduler) {
            config.schedulerType = StableDiffusionScheduler.dpmSolverMultistepScheduler
        } else {
            config.schedulerType = StableDiffusionScheduler.pndmScheduler
        }
        config.useDenoisedIntermediates = true

        // Evenly distribute previews based on inference steps
        let previewIndices = previewIndices(stepCount, previewCount)

        let images = try pipeline.generateImages(configuration: config) { progress in
            sampleTimer.stop()
            handleProgress(StableDiffusionProgress(progress: progress,
                                                   previewIndices: previewIndices),
                           sampleTimer: sampleTimer)
            if progress.stepCount != progress.step {
                sampleTimer.start()
            }
            return !canceled
        }
        let interval = Date().timeIntervalSince(beginDate)
        print("Got images: \(images) in \(interval)")
        
        // Unwrap the 1 image we asked for, nil means safety checker triggered
        let image = images.compactMap({ $0 }).first
        return GenerationResult(image: image, lastSeed: theSeed, interval: interval, userCanceled: canceled, itsPerSecond: 1.0/sampleTimer.median)
    }

    func handleProgress(_ progress: StableDiffusionProgress, sampleTimer: SampleTimer) {
        self.progress = progress
    }
        
    func setCancelled() {
        canceled = true
    }
}
