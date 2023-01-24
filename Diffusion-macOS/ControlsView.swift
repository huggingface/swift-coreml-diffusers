//
//  PromptView.swift
//  Diffusion-macOS
//
//  Created by Cyril Zakka on 1/12/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
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

//struct LabelToggleDisclosureGroupStyle: DisclosureGroupStyle {
//    func makeBody(configuration: Configuration) -> some View {
//        VStack {
//            HStack {
//                Button {
//                    withAnimation {
//                        configuration.isExpanded.toggle()
//                    }
//                } label: {
//                    Image(systemName: configuration.isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
//                }.buttonStyle(.plain).foregroundColor(.primary).colorInvert()
//                configuration.label.onTapGesture {
//                    withAnimation {
//                        configuration.isExpanded.toggle()
//                    }
//                }
//                Spacer()
//            }
//            if configuration.isExpanded {
//                configuration.content
//            }
//        }
//    }
//}

struct ControlsView: View {
    @EnvironmentObject var generation: GenerationContext

    static let models = ModelInfo.MODELS
    static let modelNames = models.map { $0.modelVersion }
    
    @State private var model = Settings.shared.currentModel.modelVersion
    @State private var disclosedModel = true
    @State private var disclosedPrompt = true
    @State private var disclosedSteps = false
    @State private var disclosedSeed = false

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
                    DisclosureGroup(isExpanded: $disclosedModel) {
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
                        Label("Model from Hub", systemImage: "cpu").foregroundColor(.secondary).onTapGesture {
                            withAnimation {
                                disclosedModel.toggle()
                            }
                        }
                    }
                    
                    Divider()
                    
                    DisclosureGroup(isExpanded: $disclosedPrompt) {
                        Group {
                            TextField("Positive prompt", text: $generation.positivePrompt,
                                      axis: .vertical).lineLimit(5)
                                .textFieldStyle(.squareBorder)
                                .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: 20))
                            TextField("Negative prompt", text: $generation.negativePrompt,
                                      axis: .vertical).lineLimit(5)
                                .textFieldStyle(.squareBorder)
                        }.padding(.leading, 10)
                    } label: {
                        Label("Prompts", systemImage: "text.quote").foregroundColor(.secondary).onTapGesture {
                            withAnimation {
                                disclosedPrompt.toggle()
                            }
                        }
                    }
                    
                    Divider()

                    DisclosureGroup(isExpanded: $disclosedSteps) {
                        CompactSlider(value: $generation.steps, in: 0...150, step: 5) {
                            Text("Steps")
                            Spacer()
                            Text("\(Int(generation.steps))")
                        }.padding(.leading, 10)
                    } label: {
                        Label("Step count", systemImage: "square.3.layers.3d.down.left").foregroundColor(.secondary).onTapGesture {
                            withAnimation {
                                disclosedSteps.toggle()
                            }
                        }
                    }
                    Divider()
                    
//                    DisclosureGroup() {
//                        CompactSlider(value: $generation.numImages, in: 0...10, step: 1) {
//                            Text("Number of Images")
//                            Spacer()
//                            Text("\(Int(generation.numImages))")
//                        }.padding(.leading, 10)
//                    } label: {
//                        Label("Number of images", systemImage: "photo.stack").foregroundColor(.secondary)
//                    }
//                    Divider()
                    
                        DisclosureGroup(isExpanded: $disclosedSeed) {
                        let sliderLabel = generation.seed < 0 ? "Random Seed" : "Seed"
                        CompactSlider(value: $generation.seed, in: -1...1000, step: 1) {
                            Text(sliderLabel)
                            Spacer()
                            Text("\(Int(generation.seed))")
                        }.padding(.leading, 10)
                    } label: {
                        Label("Seed", systemImage: "leaf").foregroundColor(.secondary).onTapGesture {
                            withAnimation {
                                disclosedSeed.toggle()
                            }
                        }
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

