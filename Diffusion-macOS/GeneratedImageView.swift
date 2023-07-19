//
//  GeneratedImageView.swift
//  Diffusion-macOS
//
//  Created by Pedro Cuenca on 18/1/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import UniformTypeIdentifiers

struct GeneratedImageView: View {
    @EnvironmentObject var generation: GenerationContext
    @EnvironmentObject var imageViewModel: ImageViewObservableModel
    @State var diffusionImageIndex: Int = -1
    @State private var isShowingInfo = false
    
    var cgImage: CGImage {
        let blankCGImage = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) , provider: CGDataProvider(data: NSData(bytes: [0, 0, 0, 0], length: 4) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        guard diffusionImageIndex >= 0 && diffusionImageIndex < imageViewModel.currentBuildImages.count else {
            if let cgImage = NSImage(imageLiteralResourceName: "placeholder").cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cgImage
            }
            return blankCGImage
        }
        if let returnImage = imageViewModel.currentBuildImages[safe: diffusionImageIndex]?.diffusionImage?.cgImage {
            return returnImage
        }
        if let symbolImage = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil) {
            if let cgImage = symbolImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cgImage
            }
        }
        print("warning: returning blank cgImage")
        // Return a default CGImage if none of the conditions are met
        return blankCGImage
    }
    
    
    var body: some View {
        if let diffusionImageWrapper = imageViewModel.currentBuildImages[safe: diffusionImageIndex] {
            
            if .generating == diffusionImageWrapper.diffusionImageState {
                switch generation.state {
                case .userCanceled:
                    return AnyView(Text("Generation canceled"))
                case .startup, .complete(_, _, _, _), .failed(_):
                    // startup, complete and failed modes should not show because these conditions will be caught in the wrapping diffusionImageWrapper.diffusionImageState conditions. When the generation.state is startup, complete or failed the diffusionImageState is not longer generating.
                    return AnyView(ProgressView())
                case .running(let progress):
                    guard let progress = progress, progress.stepCount > 0 else {
                        // The first time it takes a little bit before generation starts
                        return AnyView(ProgressView())
                    }
                    let step = Int(progress.step) + 1
                    let fraction = Double(step) / Double(progress.stepCount)
                    let label = "Step \(step) of \(progress.stepCount)"
                    
                    return AnyView(VStack {
                        Group {
                            if let safeImage = generation.previewImage {
                                Image(safeImage, scale: 1, label: Text("generated"))
                                    .resizable()
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                            }
                        }
                        HStack {
                            ProgressView(label, value: fraction, total: 1).padding()
                            Button {
                                generation.cancelGeneration()
                            } label: {
                                Image(systemName: "x.circle.fill").foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                    })
                }
            } else if .waiting == diffusionImageWrapper.diffusionImageState {
                return AnyView(
                    Image("placeholder")
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                )
            } else if .complete == diffusionImageWrapper.diffusionImageState {
                return AnyView(
                    VStack {
                        Image(nsImage: NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height)), scale: 1, label: Text("Generated image"))
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .onDrag {
                                return doOnDrag()
                            }
                            .contextMenu {
                                Button {
                                    // Action: copy the DiffusionImage to the pasteboard
                                    doCopyAction()
                                } label: {
                                    Label("Copy", systemImage: "square.and.arrow.down")
                                }
                            }
                            .onTapGesture {
                                isShowingInfo.toggle()
                            }
                        HStack {
                            Spacer()
                            Button(action: {
                                DispatchQueue.main.async {
                                    generation.seed = UInt32(diffusionImageWrapper.diffusionImage?.seed ?? 0)
                                }
                            }) {
                                Text("\(Int(diffusionImageWrapper.diffusionImage?.seed ?? 0))")
                                    .font(.headline)
                                    .padding(8)
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(RoundedRectangle(cornerRadius: 15))
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Spacer()
                            Spacer()
                            Button(action: {
                                isShowingInfo.toggle()
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.headline)
                                    .padding(8)
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .background(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        
                    }
                        .sheet(isPresented: $isShowingInfo) {
                            InfoPanel(isShowingInfo: $isShowingInfo, diffusionImage: imageViewModel.currentBuildImages[diffusionImageIndex].diffusionImage)
                        })
            }
            
            // catch fallover conditions when diffusionImage is not equal to .generating, .waiting or .complete
            return AnyView(
                Image("placeholder")
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            )
        }
        // fallover condition when diffusionImage is not found in imageViewModel
        return AnyView(
            Image("placeholder")
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 15))
        )
    }
    
    func doCopyAction() {
        if let diffusionImage = imageViewModel.currentBuildImages[diffusionImageIndex].diffusionImage {
            let pb = NSPasteboard.general
            pb.clearContents()
            
            // Create an array of NSPasteboardWriting objects
            var items: [NSPasteboardWriting] = []
            
            // Add the DiffusionImage object itself
            items.append(diffusionImage)
            pb.writeObjects(items)
        }
    }
    
    func doOnDrag() -> NSItemProvider {
        if let diffusionImage = imageViewModel.currentBuildImages[diffusionImageIndex].diffusionImage {
            let provider = NSItemProvider(object: diffusionImage)
            provider.copy()
            return provider
        }
        return NSItemProvider()
    }
    
}
