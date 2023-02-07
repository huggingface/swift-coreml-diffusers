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
    var pipelineState: Binding<PipelineState>
    
    @State private var showErrorPopover = false
    
    func submit() {
        if case .running = generation.state { return }
        Task {
            generation.state = .running(nil)
            let interval: TimeInterval?
            let image: CGImage?
            (image, interval) = await generation.generate() ?? (nil, nil)
            generation.state = .complete(generation.positivePrompt, image, interval)
        }
    }
    
    func generationStatusView() -> any View {
        switch generation.state {
        case .startup: return EmptyView()
        case .running(let progress):
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
        case .complete(_, let image, let interval):
            guard let _ = image else {
                return HStack {
                    Text("Safety checker triggered, please try a different prompt or seed")
                    Spacer()
                }
            }
                              
            return HStack {
                let intervalString = String(format: "Time: %.1fs", interval ?? 0)
                Text(intervalString)
                Spacer()
            }.frame(maxHeight: 25)
        }
    }

    var body: some View {
        switch pipelineState.wrappedValue {
        case .downloading(let progress):
            ProgressView("Downloading…", value: progress*100, total: 110).padding()
        case .uncompressing:
            ProgressView("Uncompressing…", value: 100, total: 110).padding()
        case .loading:
            ProgressView("Loading…", value: 105, total: 110).padding()
        case .ready:
            VStack {
                Button {
                    submit()
                } label: {
                    Text("Generate")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                
                AnyView(generationStatusView())
            }
        case .failed(let error):
            HStack {
                Text("Pipeline loading error")
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
    }
}

struct StatusView_Previews: PreviewProvider {
    static var previews: some View {
        StatusView(pipelineState: .constant(.downloading(0.2)))
    }
}
