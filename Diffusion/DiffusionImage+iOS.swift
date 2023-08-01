//
//  DiffusionImage+iOS.swift
//  Diffusion
//
//  Created by Dolmere and Pedro Cuenca on 30/07/2023.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

extension DiffusionImage {
    
    /// Instance func to place the generated image on the file system and return the `fileURL` where it is stored.
    func save(cgImage: CGImage, filename: String?) -> URL? {
                
        let image = UIImage(cgImage: cgImage)
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

    /// Returns a `Data` representation of this generated image in PNG format or nil if there is an error converting the image data.
    func pngRepresentation() -> Data? {
        let bitmapRep = UIImage(cgImage: cgImage).pngData()
        return bitmapRep
    }
}

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
