//
//  ShareButtons.swift
//  Diffusion-macOS
//
//  Created by Dolmere on 19/06/2023.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE

import SwiftUI

// AppKit version that uses NSImage, NSSavePanel
struct ShareButtons: View {
    var image: CGImage
    var name: String
    
    var filename: String {
        name.replacingOccurrences(of: " ", with: "_")
    }
    
    func showSavePanel() -> URL? {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save your image"
        savePanel.message = "Choose a folder and a name to store the image."
        savePanel.nameFieldLabel = "File name:"
        savePanel.nameFieldStringValue = filename

        let response = savePanel.runModal()
        return response == .OK ? savePanel.url : nil
    }

    func savePNG(cgImage: CGImage, path: URL) {
        let image = NSImage(cgImage: cgImage, size: .zero)
        let imageRepresentation = NSBitmapImageRep(data: image.tiffRepresentation!)
        guard let pngData = imageRepresentation?.representation(using: .png, properties: [:]) else {
            print("Error generating PNG data")
            return
        }
        do {
            try pngData.write(to: path)
        } catch {
            print("Error saving: \(error)")
        }
    }

    var body: some View {
        let imageView = Image(image, scale: 1, label: Text(name))
        HStack {
            ShareLink(item: imageView, preview: SharePreview(name, image: imageView))
            Button() {
                if let url = showSavePanel() {
                    savePNG(cgImage: image, path: url)
                }
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
        }
    }
}
