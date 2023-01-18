//
//  StatusView.swift
//  Diffusion-macOS
//
//  Created by Cyril Zakka on 1/12/23.
//

import SwiftUI

struct StatusView: View {
    @EnvironmentObject var generation: GenerationContext
    var pipelineState: Binding<PipelineState>
    
    func submit() {
        if case .running = generation.state { return }
        Task {
            generation.state = .running(nil)
            let interval: TimeInterval?
            let image: CGImage?
            let prompt = "Portrait of cat in a tuxedo, oil on canvas"
            (image, interval) = await generation.generate(prompt: prompt) ?? (nil, nil)
            generation.state = .complete(prompt, image, interval)
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
                
                // Generation state
                AnyView(generationStatusView())
            }
        case .failed:
            Text("Pipeline loading error")
        }
    }
}

struct StatusView_Previews: PreviewProvider {
    static var previews: some View {
        StatusView(pipelineState: .constant(.downloading(0.2)))
    }
}
