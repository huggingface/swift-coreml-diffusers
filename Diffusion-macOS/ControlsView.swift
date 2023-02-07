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

/// Mimics the native appearance, but labels are clickable.
/// To be removed (adding gestures to all labels) if we observe any UI shenanigans.
struct LabelToggleDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack {
            HStack {
                Button {
                    withAnimation {
                        configuration.isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right").frame(width:8, height: 8)
                }.buttonStyle(.plain).font(.footnote).fontWeight(.semibold).foregroundColor(.gray)
                configuration.label.onTapGesture {
                    withAnimation {
                        configuration.isExpanded.toggle()
                    }
                }
                Spacer()
            }
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

struct ControlsView: View {
    @EnvironmentObject var generation: GenerationContext

    static let models = ModelInfo.MODELS
    static let modelNames = models.map { $0.modelVersion }
    
    @State private var model = Settings.shared.currentModel.modelVersion
    @State private var disclosedModel = true
    @State private var disclosedPrompt = true
    @State private var disclosedGuidance = false
    @State private var disclosedSteps = false
    @State private var disclosedSeed = false

    // TODO: refactor download with similar code in Loading.swift (iOS)
    @State private var stateSubscriber: Cancellable?
    @State private var pipelineState: PipelineState = .downloading(0)
    @State private var pipelineLoader: PipelineLoader? = nil

    // TODO: make this computed, and observable, and easy to read
    @State private var mustShowSafetyCheckerDisclaimer = false
    
    func updateSafetyCheckerState() {
        mustShowSafetyCheckerDisclaimer = generation.disableSafety && !Settings.shared.safetyCheckerDisclaimerShown
    }
    
    func modelDidChange(model: ModelInfo) {
        print("Loading model \(model)")
        Settings.shared.currentModel = model
        
        pipelineLoader?.cancel()
        pipelineState = .downloading(0)
        Task.init {
            let loader = PipelineLoader(model: model)
            self.pipelineLoader = loader
            stateSubscriber = loader.statePublisher.sink { state in
                DispatchQueue.main.async {
                    switch state {
                    case .downloading(let progress):
                        print("\(loader.model.modelVersion): \(progress)")
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
                        Label("Model from Hub", systemImage: "cpu").foregroundColor(.secondary)
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
                        Label("Prompts", systemImage: "text.quote").foregroundColor(.secondary)
                    }
                    
                    Divider()

                    DisclosureGroup(isExpanded: $disclosedGuidance) {
                        CompactSlider(value: $generation.guidanceScale, in: 0...20, step: 0.5) {
                            Text("Guidance Scale")
                            Spacer()
                            Text(generation.guidanceScale.formatted("%.1f"))
                        }.padding(.leading, 10)
                    } label: {
                        Label("Guidance Scale", systemImage: "scalemass").foregroundColor(.secondary)
                    }
                    Divider()

                    DisclosureGroup(isExpanded: $disclosedSteps) {
                        CompactSlider(value: $generation.steps, in: 0...150, step: 5) {
                            Text("Steps")
                            Spacer()
                            Text("\(Int(generation.steps))")
                        }.padding(.leading, 10)
                    } label: {
                        Label("Step count", systemImage: "square.3.layers.3d.down.left").foregroundColor(.secondary)
                    }
                    Divider()
                                        
                    DisclosureGroup(isExpanded: $disclosedSeed) {
                        let sliderLabel = generation.seed < 0 ? "Random Seed" : "Seed"
                        CompactSlider(value: $generation.seed, in: -1...1000, step: 1) {
                            Text(sliderLabel)
                            Spacer()
                            Text("\(Int(generation.seed))")
                        }.padding(.leading, 10)
                    } label: {
                        Label("Seed", systemImage: "leaf").foregroundColor(.secondary)
                    }
                }
            }
            .disclosureGroupStyle(LabelToggleDisclosureGroupStyle())
            
            Toggle("Disable Safety Checker", isOn: $generation.disableSafety).onChange(of: generation.disableSafety) { value in
                updateSafetyCheckerState()
            }
                .popover(isPresented: $mustShowSafetyCheckerDisclaimer) {
                        VStack {
                            Text("You have disabled the safety checker").font(.title).padding(.top)
                            Text("""
                                 Please, ensure that you abide \
                                 by the conditions of the Stable Diffusion license and do not expose \
                                 unfiltered results to the public.
                                 """)
                            .lineLimit(nil)
                            .padding(.all, 5)
                            Button {
                                Settings.shared.safetyCheckerDisclaimerShown = true
                                updateSafetyCheckerState()
                            } label: {
                                Text("I Accept").frame(maxWidth: 200)
                            }
                            .padding(.bottom)
                        }
                        .frame(minWidth: 400, idealWidth: 400, maxWidth: 400)
                        .fixedSize()
                    }
            Divider()
            
            StatusView(pipelineState: $pipelineState)
        }
        .padding()
        .onAppear {
            print(PipelineLoader.models)
            modelDidChange(model: ModelInfo.from(modelVersion: model) ?? ModelInfo.v2Base)
        }
    }
}

