//
//  SingleGeneratedImageView.swift
//  Diffusion-macOS
//
//  Created by Dolmere on 14/06/2023.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct SingleGeneratedImageView: View {
    @EnvironmentObject var generation: GenerationContext
    @EnvironmentObject var imageViewModel: ImageViewObservableModel
    @State var generatedImage: DiffusionImage
    
    var cgImage: CGImage {
        if let returnImage = generatedImage.cgImage {
            return returnImage
        }
        if let symbolImage = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil) {
            if let cgImage = symbolImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cgImage
            }
        }
        // Return a default CGImage if none of the conditions are met
        return CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) , provider: CGDataProvider(data: NSData(bytes: [0, 0, 0, 0], length: 4) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
        
    var body: some View {
        Image(nsImage: NSImage(cgImage: cgImage , size: CGSize(width: cgImage.width, height: cgImage.height)))
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .onDrag {
                guard let tiffData = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height)).tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    return NSItemProvider()
                }
                
                let itemProvider = NSItemProvider()
                itemProvider.registerDataRepresentation(forTypeIdentifier: UTType.tiff.identifier, visibility: .all) { completion in
                    completion(tiffData, nil)
                    return nil
                }
                
                itemProvider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                    completion(pngData, nil)
                    return nil
                }
                
                if let fileURL = imageViewModel.createTempFile(image: NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))) {
                    let fileURLData = fileURL.absoluteString.data(using: .utf8)
                    itemProvider.registerDataRepresentation(forTypeIdentifier: NSPasteboard.PasteboardType.fileURL.rawValue, visibility: .all) { completion in
                        completion(fileURLData, nil)
                        return nil
                    }
                    return itemProvider
                }
                
                return NSItemProvider()
            }
            .onDisappear {
                for fileURL in imageViewModel.tempFilesCreated {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                    } catch {
                        print("Error removing temporary file: \(error)")
                    }
                }
                // empty the tracked temp files array
                imageViewModel.tempFilesCreated.removeAll()
            }
            .contextMenu {
                Button {
                    let pb = NSPasteboard.general
                    if let fileURL = imageViewModel.createTempFile(image: NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))) {
                        do {
                            let resourceValues = try fileURL.resourceValues(forKeys: [.contentTypeKey])
                            if let contentType = resourceValues.contentType {
                                let pasteboardType = NSPasteboard.PasteboardType(contentType.identifier)
                                pb.declareTypes([pasteboardType], owner: nil)
                                pb.writeObjects([fileURL as NSURL])
                            }
                        } catch {
                            print("cannot copy to pasteboard")
                            return
                        }
                    } else {
                        print("cannot make temp file")
                    }
                } label: {
                    Label("Copy", systemImage: "square.and.arrow.down")
                }
            }
            .onTapGesture {
                imageViewModel.toggleSelection(for: generatedImage)
            }
            .border(imageViewModel.selectedImages.contains(generatedImage) ? Color.blue : Color.clear, width: 2)
        }
}
