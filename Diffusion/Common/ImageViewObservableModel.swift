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
    
    func getApplicationSupportDirectory() -> URL? {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let appBundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        let appDirectoryURL = appSupportURL.appendingPathComponent(appBundleIdentifier)
        
        do {
            // Create the application support directory if it doesn't exist
            try fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            return appDirectoryURL
        } catch {
            print("Error creating application support directory: \(error)")
            return nil
        }
    }

    /// clear the cachedImages
    func reset() {
        //TODO: add save, autosave, etc...
        // on save write pipeline data into the PNG file
        currentBuildImages = []
    }
    
    func toggleSelection(for image: DiffusionImage) {
        if selectedImages.contains(image) {
            selectedImages.remove(image)
        } else {
            selectedImages.insert(image)
        }
    }
    
    #if os(macOS)
    func createTempFile(image: NSImage?) -> URL? {
        // Usage:
        if let appSupportURL = getApplicationSupportDirectory() {

        let fileURL = appSupportURL
            .appendingPathComponent("dragged_image")
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
        } else {
            print("Failed to retrieve Application Support Directory.")
        }

        return nil
    }
    #else
    func createTempFile(image: UIImage?) -> URL? {
        guard let image = image else {
            return nil
        }
        
        let fileManager = FileManager.default
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let fileURL = temporaryDirectoryURL
            .appendingPathComponent(UUID().uuidString)
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
