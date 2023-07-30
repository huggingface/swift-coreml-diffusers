//
//  DiffusionImage.swift
//  Diffusion
//
//  Created by Dolmere on 03/07/2023.
//

import SwiftUI
import StableDiffusion
import CoreTransferable

/// Tracking for a `DiffusionImage` generation state.
enum DiffusionImageState {
    case generating
    case waiting
    case complete
}

/// Generic custom error to use when an image generation fails.
enum DiffusionImageError: Error {
    case invalidDiffusionImage
}

/// Combination of a `DiffusionImage` and its associated `DiffusionImageState`
struct DiffusionImageWrapper {
    var diffusionImageState: DiffusionImageState = .waiting
    var diffusionImage: DiffusionImage? = nil
}

/// Model class to hold a generated image and the "recipe" data that was used to generate it
final class DiffusionImage: NSObject, Identifiable, NSCoding, NSSecureCoding {
    
    let id: UUID
    let cgImage: CGImage
    let seed: UInt32
    let steps: Double
    let positivePrompt: String
    let negativePrompt: String
    let guidanceScale: Double
    let disableSafety: Bool
    /// Note: We created a local enum Diffusion_StableDiffusionScheduler so that we can track the Scheduler used in the image recipe. The StableDiffusionScheduler enum has not got a raw type and therefore cannot conform to NSSecureCoding which we use for Copy/Drag operations.
    let scheduler: Diffusion_StableDiffusionScheduler

    /// This is a composed `String` built from the numeric `Seed` and the user supplied `positivePrompt` limited to the first 200 character and with whitespace replaced with underscore characters.
    var generatedFilename: String {
        return "\(seed)-\(positivePrompt)".first200Safe
    }

    /// The location on the file system where this generated image is stored.
    var fileURL: URL

    init(id: UUID, cgImage: CGImage, seed: UInt32, steps: Double, positivePrompt: String, negativePrompt: String, guidanceScale: Double, disableSafety: Bool, scheduler: Diffusion_StableDiffusionScheduler) {
        let genname = "\(seed)-\(positivePrompt)".first200Safe
        self.id = id
        self.cgImage = cgImage
        self.seed = seed
        self.steps = steps
        self.positivePrompt = positivePrompt
        self.negativePrompt = negativePrompt
        self.guidanceScale = guidanceScale
        self.disableSafety = disableSafety
        self.scheduler = scheduler
        // Initially set the fileURL to the top level applicationDirectory to allow running the completed instance func save() where the fileURL will be updated to the correct location.
        self.fileURL = URL.applicationDirectory
        // init the instance fully before executing an instance function
        super.init()
        if let url = save(cgImage: cgImage, filename: genname) {
            self.fileURL = url
        } else {
            fatalError("Fatal error init of DiffusionImage, cannot create image file at \(genname)")
        }
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(seed, forKey: "seed")
        coder.encode(steps, forKey: "steps")
        coder.encode(positivePrompt, forKey: "positivePrompt")
        coder.encode(negativePrompt, forKey: "negativePrompt")
        coder.encode(guidanceScale, forKey: "guidanceScale")
        coder.encode(disableSafety, forKey: "disableSafety")
        coder.encode(scheduler, forKey: "scheduler")
        // Encode cgImage as data
        if let data = pngRepresentation() {
            coder.encode(data, forKey: "cgImage")
        }
    }
    
    required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(forKey: "id") as? UUID else {
            return nil
        }
        
        self.id = id
        self.seed = UInt32(coder.decodeInt32(forKey: "seed"))
        self.steps = coder.decodeDouble(forKey: "steps")
        self.positivePrompt = coder.decodeObject(forKey: "positivePrompt") as? String ?? ""
        self.negativePrompt = coder.decodeObject(forKey: "negativePrompt") as? String ?? ""
        self.guidanceScale = coder.decodeDouble(forKey: "guidanceScale")
        self.disableSafety = coder.decodeBool(forKey: "disableSafety")
        // Should we error/throw here instead of assuming our default scheduler? -- dolmere
        self.scheduler = coder.decodeObject(forKey: "scheduler") as? Diffusion_StableDiffusionScheduler ?? Diffusion_StableDiffusionScheduler.dpmSolverMultistepScheduler
        let genname = "\(seed)-\(positivePrompt)".first200Safe
        
        // Decode cgImage from data
        if let imageData = coder.decodeObject(forKey: "cgImage") as? Data {
#if os(macOS)
            if let img = NSBitmapImageRep(data: imageData)?.cgImage {
                self.cgImage = img
            } else {
                fatalError("Fatal error loading data with missing cgImage")
            }
#else
            if let image = UIImage(data: imageData)?.cgImage {
                self.cgImage = image
            } else {
                fatalError("Fatal error loading data with missing cgImage")
            }
#endif
        } else {
            fatalError("Fatal error loading data with missing cgImage in object")
        }
        self.fileURL = URL.applicationDirectory
        super.init()
        if let url = save(cgImage: cgImage, filename: genname) {
            self.fileURL = url
        } else {
            fatalError("Fatal error init of DiffusionImage, cannot create image file at \(genname)")
        }
    }

    // MARK: - Equatable

    static func == (lhs: DiffusionImage, rhs: DiffusionImage) -> Bool {
        return lhs.id == rhs.id
    }

    // MARK: - NSSecureCoding

    static var supportsSecureCoding: Bool {
        return true
    }
}
