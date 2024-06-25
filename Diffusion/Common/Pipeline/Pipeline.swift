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
    let pipeline: StableDiffusionPipelineProtocol
    let maxSeed: UInt32
    
    var isXL: Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            return (pipeline as? StableDiffusionXLPipeline) != nil
        }
        return false
    }

    var isSD3: Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            return (pipeline as? StableDiffusion3Pipeline) != nil
        }
        return false
    }

    var progress: StableDiffusionProgress? = nil {
        didSet {
            progressPublisher.value = progress
        }
    }
    lazy private(set) var progressPublisher: CurrentValueSubject<StableDiffusionProgress?, Never> = CurrentValueSubject(progress)
    
    private var canceled = false

    init(_ pipeline: StableDiffusionPipelineProtocol, maxSeed: UInt32 = UInt32.max) {
        self.pipeline = pipeline
        self.maxSeed = maxSeed
    }
    
    func generate(
        prompt: String,
        negativePrompt: String = "",
        scheduler: StableDiffusionScheduler,
        numInferenceSteps stepCount: Int = 50,
        seed: UInt32 = 0,
        numPreviews previewCount: Int = 5,
        guidanceScale: Float = 7.5,
        disableSafety: Bool = false
    ) throws -> GenerationResult {
        let beginDate = Date()
        canceled = false
        let theSeed = seed > 0 ? seed : UInt32.random(in: 1...maxSeed)
        let sampleTimer = SampleTimer()
        sampleTimer.start()
        
        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = negativePrompt
        config.stepCount = stepCount
        config.seed = theSeed
        config.guidanceScale = guidanceScale
        config.disableSafety = disableSafety
        config.schedulerType = scheduler.asStableDiffusionScheduler()
        config.useDenoisedIntermediates = true
        if isXL {
            config.encoderScaleFactor = 0.13025
            config.decoderScaleFactor = 0.13025
            config.schedulerTimestepSpacing = .karras
        }

        if isSD3 {
            config.encoderScaleFactor = 1.5305
            config.decoderScaleFactor = 1.5305
            config.decoderShiftFactor = 0.0609
            config.schedulerTimestepShift = 3.0
        }

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
