//
//  TextToImage.swift
//  Diffusion
//
//  Created by Pedro Cuenca on December 2022.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import Combine
import StableDiffusion

// TODO: bind to UI controls
let scheduler = StableDiffusionScheduler.dpmSolverMultistepScheduler
let steps = 25
let seed: UInt32? = nil

func generate(pipeline: Pipeline?, prompt: String) async -> (CGImage, TimeInterval)? {
    guard let pipeline = pipeline else { return nil }
    return try? pipeline.generate(prompt: prompt, scheduler: scheduler, numInferenceSteps: steps, seed: seed)
}

enum GenerationState {
    case startup
    case running(StableDiffusionProgress?)
    case idle(String, TimeInterval?)
}

/// Presents "Share" + "Save" buttons on Mac; just "Share" on iOS/iPadOS.
/// This is because I didn't find a way for "Share" to show a Save option when running on macOS.
struct ShareButtons: View {
    var image: CGImage
    var name: String
    
    var filename: String {
        name.replacingOccurrences(of: " ", with: "_")
    }
    
    var body: some View {
        let imageView = Image(image, scale: 1, label: Text(name))

        if runningOnMac {
            HStack {
                ShareLink(item: imageView, preview: SharePreview(name, image: imageView))
                Button() {
                    guard let imageData = UIImage(cgImage: image).pngData() else {
                        return
                    }
                    do {
                        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).png")
                        try imageData.write(to: fileURL)
                        let controller = UIDocumentPickerViewController(forExporting: [fileURL])
                        
                        let scene = UIApplication.shared.connectedScenes.first as! UIWindowScene
                        scene.windows.first!.rootViewController!.present(controller, animated: true)
                    } catch {
                        print("Error creating file")
                    }
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
            }
        } else {
            ShareLink(item: imageView, preview: SharePreview(name, image: imageView))
        }
    }
}

struct ImageWithPlaceholder: View {
    var image: Binding<CGImage?>
    var state: Binding<GenerationState>
        
    var body: some View {
        switch state.wrappedValue {
        case .startup: return AnyView(Image("placeholder").resizable())
        case .running(let progress):
            guard let progress = progress, progress.stepCount > 0 else {
                // The first time it takes a little bit before generation starts
                return AnyView(ProgressView())
            }
            let step = Int(progress.step) + 1
            let fraction = Double(step) / Double(progress.stepCount)
            let label = "Step \(step) of \(progress.stepCount)"
            return AnyView(ProgressView(label, value: fraction, total: 1).padding())
        case .idle(let lastPrompt, let interval):
            guard let theImage = image.wrappedValue else {
                return AnyView(Image(systemName: "exclamationmark.triangle").resizable())
            }
                              
            let imageView = Image(theImage, scale: 1, label: Text("generated"))
            return AnyView(
                VStack {
                    imageView.resizable().clipShape(RoundedRectangle(cornerRadius: 20))
                    HStack {
                        let intervalString = String(format: "Time: %.1fs", interval ?? 0)
                        Rectangle().fill(.clear).overlay(Text(intervalString).frame(maxWidth: .infinity, alignment: .leading).padding(.leading))
                        Rectangle().fill(.clear).overlay(
                            HStack {
                                Spacer()
                                ShareButtons(image: theImage, name: lastPrompt).padding(.trailing)
                            }
                        )
                    }.frame(maxHeight: 25)
            })
        }
    }
}

struct TextToImage: View {
    @EnvironmentObject var context: DiffusionGlobals

    @State private var prompt = "Labrador in the style of Vermeer"
    @State private var image: CGImage? = nil
    @State private var state: GenerationState = .startup
    
    @State private var progressSubscriber: Cancellable?

    func submit() {
        if case .running = state { return }
        Task {
            state = .running(nil)
            let interval: TimeInterval?
            (image, interval) = await generate(pipeline: context.pipeline, prompt: prompt) ?? (nil, nil)
            state = .idle(prompt, interval)
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                TextField("Prompt", text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submit()
                    }
                Button("Generate") {
                    submit()
                }
                .padding()
                .buttonStyle(.borderedProminent)
            }
            ImageWithPlaceholder(image: $image, state: $state)
                .scaledToFit()
            Spacer()
        }
        .padding()
        .onAppear {
            progressSubscriber = context.pipeline!.progressPublisher.sink { progress in
                guard let progress = progress else { return }
                state = .running(progress)
            }
        }
    }
}
