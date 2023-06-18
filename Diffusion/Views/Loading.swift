//
//  Loading.swift
//  Diffusion
//
//  Created by Pedro Cuenca on December 2022.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import Combine

let model = deviceSupportsQuantization ? ModelInfo.v21Palettized : ModelInfo.v21Base

struct LoadingView: View {
    @ObservedObject var modelsViewModel: ModelsViewModel = ModelsViewModel(settings: Settings.shared)
    @StateObject var generation = GenerationContext()

    @State private var preparationPhase = "Downloading…"
    @State private var downloadProgress: Double = 0
    
    enum CurrentView {
        case loading
        case textToImage
        case error(String)
    }
    @State private var currentView: CurrentView = .loading
    
    @State private var stateSubscriber: Cancellable?

    var body: some View {
        VStack {
            switch currentView {
            case .textToImage: TextToImage().transition(.opacity)
            case .error(let message): ErrorPopover(errorMessage: message).transition(.move(edge: .top))
            case .loading:
                // TODO: Don't present progress view if the pipeline is cached
                ProgressView(preparationPhase, value: downloadProgress, total: 1).padding()
            }
        }
        .animation(.easeIn, value: currentView)
        .environmentObject(generation)
        .onAppear {
            Task.init {
                let loader = PipelineLoader(model: model, modelsViewModel: modelsViewModel)
                stateSubscriber = loader.statePublisher.sink { state in
                    DispatchQueue.main.async {
                        switch state {
                        case .downloading(let progress):
                            preparationPhase = "Downloading"
                            downloadProgress = progress
                        case .uncompressing:
                            preparationPhase = "Uncompressing"
                            downloadProgress = 1
                        case .readyOnDisk:
                            preparationPhase = "Loading"
                            downloadProgress = 1
                        default:
                            break
                        }
                    }
                }
                do {
                    generation.pipeline = try await loader.prepareDownload()
                    self.currentView = .textToImage
                } catch {
                    self.currentView = .error("Could not load model, error: \(error)")
                }
            }            
        }
    }
}

// Required by .animation
extension LoadingView.CurrentView: Equatable {}

struct ErrorPopover: View {
    var errorMessage: String

    var body: some View {
        Text(errorMessage)
            .font(.headline)
            .padding()
            .foregroundColor(.red)
            .background(Color.white)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingView()
    }
}
