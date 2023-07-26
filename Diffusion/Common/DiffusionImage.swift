//
//  DiffusionImage.swift
//  Diffusion
//
//  Created by Dolmere on 03/07/2023.
//

import SwiftUI
import StableDiffusion
import CoreTransferable
import UniformTypeIdentifiers
#if os(macOS)
#else
import UIKit // Access to UIImage on iOS
#endif

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

/// Model class  to hold a  generated image and the data used to generate it
final class DiffusionImage: NSObject, Identifiable, NSCoding, NSSecureCoding {
    
    // Note: we do not capture the chosen Scheduler as it's a Swift enum and cannot conform to NSSecureCoding, which is used for Drag operations.
    let id: UUID
    let cgImage: CGImage
    let seed: UInt32
    let steps: Double
    let positivePrompt: String
    let negativePrompt: String
    let guidanceScale: Double
    let disableSafety: Bool

    /// This is a composed `String` built from the numeric `Seed` and the user supplied `positivePrompt` limited to the first 200 character and with whitespace replaced with underscore characters.
    var generatedFilename: String {
        return "\(seed)-\(positivePrompt)".first200Safe
    }

    /// The location on the file system where this generated image is stored.
    var fileURL: URL

    init(id: UUID, cgImage: CGImage, seed: UInt32, steps: Double, positivePrompt: String, negativePrompt: String, guidanceScale: Double, disableSafety: Bool) {
        let genname = "\(seed)-\(positivePrompt)".first200Safe
        self.id = id
        self.cgImage = cgImage
        self.seed = seed
        self.steps = steps
        self.positivePrompt = positivePrompt
        self.negativePrompt = negativePrompt
        self.guidanceScale = guidanceScale
        self.disableSafety = disableSafety
#if os(macOS)
        // Initially set the fileURL to the top level applicationDirectory to allow running the completed instance func save() where the fileURL will be updated to the correct location.
        self.fileURL = URL.applicationDirectory
        // init the instance fully before executing an instance function
        super.init()
        if let url = save(image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)), filename: genname) {
            self.fileURL = url
        } else {
            fatalError("Fatal error init of DiffusionImage, cannot create image file at \(genname)")
        }
#else
        // Initially set the fileURL to the top level applicationDirectory to allow running the completed instance func save() where the fileURL will be updated to the correct location.
        self.fileURL = URL.applicationDirectory
        // init the instance fully before executing an instance function
        super.init()
        if let url = save(image: UIImage(cgImage: cgImage), filename: genname) {
            self.fileURL = url
        } else {
            fatalError("Fatal error init of DiffusionImage, cannot create image file at \(genname)")
        }
#endif
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(seed, forKey: "seed")
        coder.encode(steps, forKey: "steps")
        coder.encode(positivePrompt, forKey: "positivePrompt")
        coder.encode(negativePrompt, forKey: "negativePrompt")
        coder.encode(guidanceScale, forKey: "guidanceScale")
        coder.encode(disableSafety, forKey: "disableSafety")
        // Encode cgImage as data
#if os(macOS)
        let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        coder.encode(data, forKey: "cgImage")
#else
        if let data = pngRepresentation() {
            coder.encode(data, forKey: "cgImage")
        }
#endif
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
        let genname = "\(seed)-\(positivePrompt)".first200Safe
        
        // Decode cgImage from data
#if os(macOS)
        if let imageData = coder.decodeObject(forKey: "cgImage") as? Data {
            if let img = NSBitmapImageRep(data: imageData)?.cgImage {
                self.cgImage = img
            } else {
                fatalError("Fatal error loading data with missing cgImage")
            }
        } else {
            fatalError("Fatal error loading data with missing cgImage in object")
        }
        self.fileURL = URL.applicationDirectory
        super.init()
        if let url = save(image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)), filename: genname) {
            self.fileURL = url
        } else {
            fatalError("Fatal error init of DiffusionImage, cannot create temp file at \(genname)")
        }
#else
        // Decode cgImage from data
        if let imageData = coder.decodeObject(forKey: "imageData") as? Data {
           if let image = UIImage(data: imageData) {
               if let cgImage = image.cgImage {
                   self.cgImage = cgImage
               } else {
                   fatalError("Fatal error loading data with missing cgImage")
               }
           } else {
               fatalError("Fatal error loading data with missing image")
           }
       } else {
           fatalError("Fatal error loading data with missing imageData in object")
       }
        self.fileURL = URL.applicationDirectory
        super.init()
        if let url = save(image: UIImage(cgImage: cgImage), filename: genname) {
            self.fileURL = url
        } else {
            fatalError("Fatal error init of DiffusionImage, cannot create temp file at \(genname)")
        }
#endif

    }
    
    // MARK: - Equatable

    static func == (lhs: DiffusionImage, rhs: DiffusionImage) -> Bool {
        return lhs.id == rhs.id
    }
        
    // MARK: - NSSecureCoding
    
    static var supportsSecureCoding: Bool {
        return true
    }

#if os(macOS)
    /// Instance func to place the generated image on the file system and return the `fileURL` where it is stored.
    func save(image: NSImage?, filename: String?) -> URL? {
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
                return fileURL
            } catch {
                print("Error saving image to temporary file: \(error)")
            }
        }
        return nil
    }
#else
    func save(image: UIImage?, filename: String?) -> URL? {
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
                return fileURL
            } catch {
                print("Error saving image to temporary file: \(error)")
            }
        }
        
        return nil
    }
#endif
}

#if os(macOS)
extension DiffusionImage: NSItemProviderWriting {

    // MARK: - NSItemProviderWriting

    static var writableTypeIdentifiersForItemProvider: [String] {
        return [UTType.data.identifier, UTType.png.identifier, UTType.fileURL.identifier]
    }
    
    func itemProviderVisibilityForRepresentation(withTypeIdentifier typeIdentifier: String) -> NSItemProviderRepresentationVisibility {
        return .all
    }
    
    func itemProviderRepresentation(forTypeIdentifier typeIdentifier: String) throws -> NSItemProvider {
        print("itemProviderRepresentation(forTypeIdentifier")
        print(typeIdentifier)
        let data = try NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true)
        let itemProvider = NSItemProvider()
        itemProvider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: NSItemProviderRepresentationVisibility.all) { completion in
            completion(data, nil)
            return nil
        }
        return itemProvider
    }
    
    func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping @Sendable (Data?, Error?) -> Void) -> Progress? {
        if typeIdentifier == NSPasteboard.PasteboardType.fileURL.rawValue {
            // Retrieve the file's data representation
            let data = fileURL.dataRepresentation
            completionHandler(data, nil)
        } else if typeIdentifier == UTType.png.identifier {
            // Retrieve the PNG data representation
            let data = pngRepresentation()
            completionHandler(data, nil)
        } else {
            // Indicate that the specified typeIdentifier is not supported
            let error = NSError(domain: "com.huggingface.diffusion", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported typeIdentifier"])
            completionHandler(nil, error)
        }
        return nil
    }
    
}

extension DiffusionImage: NSPasteboardWriting {
    
    // MARK: - NSPasteboardWriting

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        return [
            NSPasteboard.PasteboardType.fileURL,
            NSPasteboard.PasteboardType(rawValue: UTType.png.identifier)
        ]
    }
    
    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == NSPasteboard.PasteboardType.fileURL {
            
            // Return the file's data' representation
            return fileURL.dataRepresentation
            
        } else if type.rawValue == UTType.png.identifier {
            
            // Return a PNG data representation
            return pngRepresentation()
        }

        return nil
    }
    
}
#else
extension DiffusionImage {

    // MARK: - UIPasteboardWriting

    func writableTypeIdentifiers(for pasteboard: UIPasteboard) -> [String] {
        return [UTType.png.identifier]
    }

    func itemProviders(forActivityType activityType: UIActivity.ActivityType?) -> [NSItemProvider] {
        let itemProvider = NSItemProvider()
        itemProvider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            guard let pngData = self.pngRepresentation() else {
                completion(nil, NSError(domain: "DiffusionImageErrorDomain", code: 0, userInfo: nil))
                return nil
            }
            completion(pngData, nil)
            return nil
        }
        return [itemProvider]
    }
}
#endif

#if os(macOS)
extension DiffusionImage {
    /// Returns a `Data` representation of this generated image in PNG format or nil if there is an error converting the image data.
    func pngRepresentation() -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }
}
#else
extension DiffusionImage {
    /// Returns a `Data` representation of this generated image in PNG format or nil if there is an error converting the image data.
    func pngRepresentation() -> Data? {
        let bitmapRep = UIImage(cgImage: cgImage).pngData()
        return bitmapRep
    }
}
#endif
