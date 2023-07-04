//
//  ImageViewObservableModel.swift
//  Diffusion
//
//  Created by Dolmere on 14/06/2023.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import StableDiffusion
import CoreTransferable
import UniformTypeIdentifiers

class ImageViewObservableModel: ObservableObject {

    // Start with a placeholder position for one Diffusion image
    @MainActor
    @Published var currentBuildImages: [DiffusionImageWrapper] = [DiffusionImageWrapper(diffusionImageState: .waiting, diffusionImage: nil)]

    @MainActor
    @Published var imageCount: Int = 1 {
        didSet {
            let currentCount = self.currentBuildImages.count
            let desiredCount = self.imageCount
            
            if desiredCount > currentCount {
                // Append additional array space to match the desired count
                let placeholders = Array<DiffusionImage?>(repeating: nil, count: desiredCount - currentCount)
                addDiffusionImages(placeholders)
            } else if desiredCount < currentCount {
                // Trim excess images to match the desired count
                self.currentBuildImages = Array(self.currentBuildImages.prefix(desiredCount))
            }
        }
    }
    
    static let shared: ImageViewObservableModel = ImageViewObservableModel()
    @Published var userCanceled = false
    @Published var isGeneratingBatch = false
    
    private init() {}
    
    @MainActor
    fileprivate func makeDiffusionImage(_ generation: GenerationContext, _ img: CGImage, _ result: GenerationResult, _ state: DiffusionImageState) -> DiffusionImage {
        return DiffusionImage(id: UUID(), cgImage: img, seed: UInt32(result.lastSeed), steps: generation.steps, positivePrompt: generation.positivePrompt, negativePrompt: generation.negativePrompt, guidanceScale: generation.guidanceScale, disableSafety: generation.disableSafety)
    }
    
    // Function to update the diffusion image state
    @MainActor
    func updateDiffusionImageState(atIndex index: Int, newState: DiffusionImageState) {
        guard index >= 0, index < currentBuildImages.count else {
            return
        }
        currentBuildImages[index].diffusionImageState = newState
    }
    
    // Function to add a new diffusion image
    @MainActor
    func addDiffusionImage(_ image: DiffusionImage) {
        let tracker = DiffusionImageWrapper(diffusionImage: image)
        currentBuildImages.append(tracker)
    }
    
    @MainActor
    func addDiffusionImages(_ images: [DiffusionImage?]) {
        let placeholders = Array<DiffusionImage?>(repeating: nil, count: images.count)
        let wrappers = placeholders.map { DiffusionImageWrapper(diffusionImage: $0) }
        currentBuildImages.append(contentsOf: wrappers)
    }

    
    // Function to remove a diffusion image
    @MainActor
    func removeDiffusionImage(atIndex index: Int) {
        guard index >= 0, index < currentBuildImages.count else {
            return
        }
        currentBuildImages.remove(at: index)
    }

    public func cancelBatchGeneration() {
        userCanceled = true
        isGeneratingBatch = false
    }

    // Generate the number of images requested, continue generating until the number of requested images have been created
    public func generate(generation: GenerationContext) async {

        // If we're already running return
        if isGeneratingBatch { return }

//        if case .running = generation.state { return }

        DispatchQueue.main.asyncAndWait {
            self.isGeneratingBatch = true
            self.userCanceled = false
        }
        var currentIndex = 0

        while (isGeneratingBatch && userCanceled == false) {

            switch generation.state {
            case .userCanceled:
                DispatchQueue.main.asyncAndWait {
                    self.userCanceled = true
                    self.isGeneratingBatch = false
                }
            case .startup, .running(_), .complete(_, _, _, _), .failed(_):
                DispatchQueue.main.asyncAndWait {
                    generation.state = .running(nil)
                }
                await generateOneImage(generation: generation, forIndex: currentIndex)
                currentIndex += 1
            }
            if await currentIndex >= imageCount {
                DispatchQueue.main.asyncAndWait {
                    self.isGeneratingBatch = false
                }
            }
                
        }
    }

    @MainActor
    private func generateOneImage(generation: GenerationContext, forIndex index: Int) async {
        guard index >= 0 && index < currentBuildImages.count else {
            return
        }
        currentBuildImages[index].diffusionImageState = .generating

        var successfulImageGenerated = false
        while !successfulImageGenerated {
            do {
                let result = try await generation.generate()
                if result.userCanceled {
                    generation.cancelGeneration()
                    self.userCanceled = true
                    self.isGeneratingBatch = false
                    // reset the image state to waiting after it has cancelled
                    currentBuildImages[index].diffusionImageState = .waiting
                    return
                } else {
                    if result.images != [nil] {
                        if let img = result.images.first! {
                            currentBuildImages[index].diffusionImage = DiffusionImage(id: UUID(), cgImage: img, seed: UInt32(result.lastSeed), steps: generation.steps, positivePrompt: generation.positivePrompt, negativePrompt: generation.negativePrompt, guidanceScale: generation.guidanceScale, disableSafety: generation.disableSafety)
                            currentBuildImages[index].diffusionImageState = .complete
                            generation.state = .complete(generation.positivePrompt, [img], result.lastSeed, result.interval)
                            successfulImageGenerated = true
                            // Success. Increment the seed for the next run if in batch mode.
                            generation.overrideSeed = UInt32(result.lastSeed + 1)
                            return
                        }
                    } else {
                        // Safety check catch, increment and try again
                        generation.overrideSeed = UInt32(result.lastSeed + 1)
                    }
                }
            } catch {
                // image generation failed. Increment the seed and try again.
                generation.state = .failed(error)
                generation.overrideSeed = UInt32(generation.seed + 1)
                return
            }
        }
    }
}
