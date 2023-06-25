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
        Image(nsImage: NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height)))
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .onDrag {
                var provider = NSItemProvider()
                switch generation.state {
                case .complete(_, _, let lastSeed, _):
                    // Register the file URL
                    let generatedFilename = generation.positivePrompt.first200Safe + "-\(lastSeed)"
                    let img = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
                    if let fileURL = imageViewModel.createTempFile(image: img, filename: generatedFilename) {
                        provider = NSItemProvider(item: fileURL as NSSecureCoding, typeIdentifier: UTType.fileURL.identifier)
                        provider.suggestedName = fileURL.lastPathComponent
                        return provider
                    }
                    return provider
                case .startup, .running(_), .userCanceled, .failed(_):
                    return provider
                }
            }

            .onDisappear {
                // Clean up our temp files
                imageViewModel.reset()
            }
            .contextMenu {
                Button {
                    let pb = NSPasteboard.general
                    let img = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
                    let filename = generation.positivePrompt.first200Safe + "\(generation.seed)"
                    if let fileURL = imageViewModel.createTempFile(image: img, filename: filename) {
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
