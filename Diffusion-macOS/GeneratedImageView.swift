//
//  GeneratedImageView.swift
//  Diffusion
//
//  Created by Pedro Cuenca on 18/1/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI

struct GeneratedImageView: View {
    @EnvironmentObject var generation: GenerationContext
    @EnvironmentObject var imageViewModel: ImageViewObservableModel
    
    func completeView(generatedImages: [CGImage?]) -> some View {
        if generatedImages.count == 0 {
            return AnyView(
                Image(systemName: "exclamationmark.triangle")
                    .resizable()
            )
        } else if generatedImages.count == 1 {
            DispatchQueue.main.async {
                imageViewModel.currentBuildImages = DiffusionImage.fromCGImages(generatedImages, seed: generation.seed, steps: generation.steps, prompt: generation.positivePrompt, negativePrompt: generation.negativePrompt, scheduler: generation.scheduler, guidanceScale: generation.guidanceScale, disableSafety: generation.disableSafety)
            }
            if let img = imageViewModel.currentBuildImages.first?.cgImage {
                if let diffusionImage = DiffusionImage.fromCGImages([img], seed: generation.seed, steps: generation.steps, prompt: generation.positivePrompt, negativePrompt: generation.negativePrompt, scheduler: generation.scheduler, guidanceScale: generation.guidanceScale, disableSafety: generation.disableSafety).first {
                    return AnyView(SingleGeneratedImageView(generatedImage: diffusionImage )
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(15)
                        .environmentObject(imageViewModel)
                    )
                }
                // DiffusionImage failed to create
                // Display error condition for image not found
                return AnyView( Image(systemName: "exclamationmark.triangle")
                        .resizable()
                        .foregroundColor(.orange)
                )

            }
            // Generated image is missing
            // Display error condition for image not found, either a generation error or safety checker triggered
            return AnyView( Image(systemName: "exclamationmark.triangle")
                    .resizable()
                    .foregroundColor(.red)
            )
        } else {
            DispatchQueue.main.async {
                imageViewModel.currentBuildImages = DiffusionImage.fromCGImages(generatedImages, seed: generation.seed, steps: generation.steps, prompt: generation.positivePrompt, negativePrompt: generation.negativePrompt, scheduler: generation.scheduler, guidanceScale: generation.guidanceScale, disableSafety: generation.disableSafety)
            }
                if let _ = imageViewModel.currentBuildImages.first?.cgImage {
                    
                    return AnyView( MultipleGeneratedImagesView(generatedImages: imageViewModel.currentBuildImages)
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(15)
                        .environmentObject(imageViewModel)
                    )
                }
            
            // Display error condition for image not found
            return AnyView( Image(systemName: "exclamationmark.triangle")
                    .resizable()
                    .foregroundColor(.orange)
            )
        }
    }
    
    var body: some View {
        switch generation.state {
        case .startup: return AnyView(
            Image("placeholder")
                .resizable()
            )
        case .running(let progress):
            guard let progress = progress, progress.stepCount > 0 else {
                // The first time it takes a little bit before generation starts
                return AnyView(ProgressView())
            }
            let step = Int(progress.step) + 1
            let fraction = Double(step) / Double(progress.stepCount)
            //TODO: If multiple images are being generated then either create multiple progress bars, one per image, or multiply the step count yb the number of images... -- Dolmere
            let label = "Step \(step) of \(progress.stepCount)"
            return AnyView(HStack {
                ProgressView(label, value: fraction, total: 1).padding()
            })
        case .complete(_, let generatedImages, _, _):
            return AnyView(completeView(generatedImages: generatedImages))
        case .failed(_):
            return AnyView(Image(systemName: "exclamationmark.triangle").resizable())
        case .userCanceled:
            return AnyView(Text("Generation canceled"))
        }
    }
}
