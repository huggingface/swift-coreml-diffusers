//
//  ImageViewObservableModel.swift
//  Diffusion
//
//  Created by Dolmere on 14/06/2023.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import StableDiffusion

// Model to capture generated image data
struct DiffusionImage: Identifiable, Hashable, Equatable {
    let id = UUID()
    let cgImage: CGImage?
    let seed: Double
    let steps: Double
    let prompt: String
    let negativePrompt: String
    let scheduler: StableDiffusionScheduler
    let guidanceScale: Double
    let disableSafety: Bool

    // Function to create an array of DiffusionImage from an array of CGImage?
    static func fromCGImages(_ cgImages: [CGImage?], seed: Double, steps: Double, prompt: String, negativePrompt: String, scheduler: StableDiffusionScheduler, guidanceScale: Double, disableSafety: Bool) -> [DiffusionImage] {
        var diffusionImages: [DiffusionImage] = []
        
        for cgImage in cgImages {
            if let image = cgImage {
                let diffusionImage = DiffusionImage(
                    cgImage: image,
                    seed: seed,
                    steps: steps,
                    prompt: prompt,
                    negativePrompt: negativePrompt,
                    scheduler: scheduler,
                    guidanceScale: guidanceScale,
                    disableSafety: disableSafety
                )
                diffusionImages.append(diffusionImage)
            }
        }
        
        return diffusionImages
    }
}

class ImageViewObservableModel: ObservableObject {
    @Published var selectedImages: Set<DiffusionImage> = []
    @Published var currentBuildImages: [DiffusionImage] = []
    @Published var tempFilesCreated: [URL] = []

    static let shared: ImageViewObservableModel = ImageViewObservableModel()
    
    private init() {}
    
    /// clear the cachedImages
    func reset() {
        currentBuildImages.removeAll()
        //delete the temp storage directory to clear out cached data on disk
        let tempStorageURL = Settings.shared.tempStorageURL()
        do {
            try FileManager.default.removeItem(at: tempStorageURL)
        } catch {
            print("Failed to delete: \(tempStorageURL), error: \(error.localizedDescription)")
        }
    }
    
    func toggleSelection(for image: DiffusionImage) {
        if selectedImages.contains(image) {
            selectedImages.remove(image)
        } else {
            selectedImages.insert(image)
        }
    }
    
    #if os(macOS)
    func createTempFile(image: NSImage?, filename: String?) -> URL? {
        let appSupportURL = Settings.shared.tempStorageURL()
        let fn = filename ?? "diffusion_generated_image"
        let fileURL = appSupportURL
            .appendingPathComponent(fn)
            .appendingPathExtension("png")

        // Save the image as a temporary file
        if let tiffData = image?.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: fileURL)
                self.tempFilesCreated.append(fileURL)
                return fileURL
            } catch {
                print("Error saving image to temporary file: \(error)")
            }
        }

        return nil
    }
    #else
    func createTempFile(image: UIImage?, filename: String?) -> URL? {
        guard let image = image else {
            return nil
        }
        let fn = filename ?? "diffusion_generated_image"
        let appSupportURL = Settings.shared.tempStorageURL()

        let fileURL = appSupportURL
            .appendingPathComponent(fn)
            .appendingPathExtension("png")
        
        if let imageData = image.pngData() {
            do {
                try imageData.write(to: fileURL)
                self.tempFilesCreated.append(fileURL)
                return fileURL
            } catch {
                print("Error saving image to temporary file: \(error)")
            }
        }
        
        return nil
    }
    #endif
}
