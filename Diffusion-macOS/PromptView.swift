//
//  PromptView.swift
//  Diffusion-macOS
//
//  Created by Cyril Zakka on 1/12/23.
//

import Combine
import SwiftUI
import CompactSlider

enum PipelineState {
    case downloading(Double)
    case uncompressing
    case loading
    case ready
    case failed(Error)
}

struct PromptView: View {
    @EnvironmentObject var generation: GenerationContext

    static let models = ModelInfo.MODELS
    static let modelNames = models.map { $0.modelVersion }
    
    @State private var model = Settings.shared.currentModel.modelVersion
    @State private var positivePrompt = "Labrador in the style of Vermeer"
    @State private var negativePrompt = ""
    @State private var steps = 25.0
    @State private var numImages = 1.0
    @State private var seed = 386.0
    @State private var disclosedPrompt = true
    
    // TODO: refactor download with similar code in Loading.swift (iOS)
    @State private var stateSubscriber: Cancellable?
    @State private var pipelineState: PipelineState = .downloading(0)

    func modelDidChange(model: ModelInfo) {
        print("Loading model \(model)")
        Settings.shared.currentModel = model
        
        pipelineState = .downloading(0)
        Task.init {
            let loader = PipelineLoader(model: model)
            stateSubscriber = loader.statePublisher.sink { state in
                DispatchQueue.main.async {
                    switch state {
                    case .downloading(let progress):
                        pipelineState = .downloading(progress)
                    case .uncompressing:
                        pipelineState = .uncompressing
                    case .readyOnDisk:
                        pipelineState = .loading
                    default:
                        break
                    }
                }
            }
            do {
                generation.pipeline = try await loader.prepare()
                pipelineState = .ready
            } catch {
                print("Could not load model, error: \(error)")
                pipelineState = .failed(error)
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            
            Label("Adjustments", systemImage: "gearshape.2")
                .font(.headline)
                .fontWeight(.bold)
            Divider()
            
            ScrollView {
                Group {
                    DisclosureGroup {
                        Picker("", selection: $model) {
                            ForEach(Self.modelNames, id: \.self) {
                                Text($0)
                            }
                        }
                        .onChange(of: model) { theModel in
                            guard let model = ModelInfo.from(modelVersion: theModel) else { return }
                            modelDidChange(model: model)
                        }
                    } label: {
                        Label("Model", systemImage: "cpu").foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    DisclosureGroup(isExpanded: $disclosedPrompt) {
                        Group {
                            TextField("Positive prompt", text: $positivePrompt,
                                      axis: .vertical).lineLimit(5)
                                .textFieldStyle(.squareBorder)
                                .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: 20))
                            TextField("Negative prompt", text: $negativePrompt,
                                      axis: .vertical).lineLimit(5)
                                .textFieldStyle(.squareBorder)
                        }.padding(.leading, 10)
                    } label: {
                        Label("Prompts", systemImage: "text.quote").foregroundColor(.secondary)
                    }
                    
                    Divider()

                    DisclosureGroup {
                        CompactSlider(value: $steps, in: 0...150, step: 5) {
                            Text("Steps")
                            Spacer()
                            Text("\(Int(steps))")
                        }.padding(.leading, 10)
                    } label: {
                        Label("Step count", systemImage: "square.3.layers.3d.down.left").foregroundColor(.secondary)
                    }

                    Divider()
                    DisclosureGroup() {
                        CompactSlider(value: $numImages, in: 0...10, step: 1) {
                            Text("Number of Images")
                            Spacer()
                            Text("\(Int(numImages))")
                        }.padding(.leading, 10)
                    } label: {
                        Label("Number of images", systemImage: "photo.stack").foregroundColor(.secondary)
                    }
                    Divider()
                    DisclosureGroup() {
                        CompactSlider(value: $seed, in: 0...1000, step: 1) {
                            Text("Random seed")
                            Spacer()
                            Text("\(Int(seed))")
                        }.padding(.leading, 10)
                    } label: {
                        Label("Random Seed", systemImage: "leaf").foregroundColor(.secondary)
                    }
                }
            }
            
            StatusView(pipelineState: $pipelineState)
        }
        .padding()
        .onAppear {
            print(PipelineLoader.models)
            modelDidChange(model: ModelInfo.from(modelVersion: model) ?? ModelInfo.v2Base)
        }
    }
}

