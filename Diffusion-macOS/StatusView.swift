//
//  StatusView.swift
//  Diffusion-macOS
//
//  Created by Cyril Zakka on 1/12/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI

struct StatusView: View {
    @EnvironmentObject var generation: GenerationContext
    @EnvironmentObject var imageViewModel: ImageViewObservableModel
    var pipelineState: Binding<PipelineState>
    
    @State private var showErrorPopover = false
    
    func submit() async {
        // reset overrideSeed to ensure no leftover previous run info.
        generation.overrideSeed = 0
        await imageViewModel.generate(generation: generation)
    }

    func errorWithDetails(_ message: String, error: Error) -> any View {
        HStack {
            Text(message)
            Spacer()
            Button {
                showErrorPopover.toggle()
            } label: {
                Image(systemName: "info.circle")
            }.buttonStyle(.plain)
            .popover(isPresented: $showErrorPopover) {
                VStack {
                    Text(verbatim: "\(error)")
                    .lineLimit(nil)
                    .padding(.all, 5)
                    Button {
                        showErrorPopover.toggle()
                    } label: {
                        Text("Dismiss").frame(maxWidth: 200)
                    }
                    .padding(.bottom)
                }
                .frame(minWidth: 400, idealWidth: 400, maxWidth: 400)
                .fixedSize()
            }
        }
    }

    func generationStatusView() -> any View {
        switch generation.state {
        case .startup: return EmptyView()
        case .running(let progress):
            if imageViewModel.isGeneratingBatch {
                guard let progress = progress, progress.stepCount > 0 else {
                    // The first time it takes a little bit before generation starts
                    return HStack {
                        Text("Preparing model…")
                        Spacer()
                    }
                }
                let step = Int(progress.step) + 1
                let fraction = Double(step) / Double(progress.stepCount)
                return HStack {
                    Text("Generating \(Int(round(100*fraction)))%")
                    Spacer()
                }
            } else {
                return EmptyView()
            }
        case .complete(_, let images, let lastSeed, let interval):
            guard let _ = images.first else {
                return HStack {
                    Text("Safety checker triggered, please try a different prompt or seed.")
                    Spacer()
                }
            }
                              
            return HStack {
                let intervalString = String(format: "Time: %.1fs", interval ?? 0)
                Text(intervalString)
                Spacer()
                if generation.seed != UInt32(lastSeed) {
                    Text("Seed: \(lastSeed)")
                    Button("Set") {
                        generation.seed = UInt32(lastSeed)
                    }
                }
            }.frame(maxHeight: 25)
        case .failed(let error):
            return errorWithDetails("Generation error", error: error)
        case .userCanceled:
            return HStack {
                Text("Generation canceled.")
                Spacer()
            }
        }
    }
    
    var body: some View {
        switch pipelineState.wrappedValue {
        case .downloading(let progress):
            return AnyView(ProgressView("Downloading…", value: progress*100, total: 110).padding())
        case .uncompressing:
            return AnyView(ProgressView("Uncompressing…", value: 100, total: 110).padding())
        case .loading:
            return AnyView(ProgressView("Loading…", value: 105, total: 110).padding())
        case .ready:
            if imageViewModel.isGeneratingBatch {
                return AnyView(VStack {
                    Button {
                        generation.cancelGeneration()
                        imageViewModel.cancelBatchGeneration()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundColor(.orange)

                    AnyView(generationStatusView())
                })
            } else {
                return AnyView(VStack {
                    Button {
                        Task {
                            await submit()
                        }
                    } label: {
                        Text("Generate")
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)

                    AnyView(generationStatusView())
                })
            }
        case .failed(let error):
            return AnyView(errorWithDetails("Pipeline loading error", error: error))
        }
    }
}

struct StatusView_Previews: PreviewProvider {
    static var previews: some View {
        StatusView(pipelineState: .constant(.downloading(0.2)))
    }
}
