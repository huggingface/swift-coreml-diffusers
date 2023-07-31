//
//  DiffusionImage+macOS.swift
//  Diffusion-macOS
//
//  Created by Dolmere and Pedro Cuenca on 30/07/2023.
//

import SwiftUI
import UniformTypeIdentifiers

extension DiffusionImage {
    
    /// Instance func to place the generated image on the file system and return the `fileURL` where it is stored.
    func save(cgImage: CGImage, filename: String?) -> URL? {
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            
        let appSupportURL = Settings.shared.tempStorageURL()
        let fn = filename ?? "diffusion_generated_image"
        let fileURL = appSupportURL
            .appendingPathComponent(fn)
            .appendingPathExtension("png")
        
        // Save the image as a temporary file
        if let tiffData = nsImage.tiffRepresentation,
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

    /// Returns a `Data` representation of this generated image in PNG format or nil if there is an error converting the image data.
    func pngRepresentation() -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }
}

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
