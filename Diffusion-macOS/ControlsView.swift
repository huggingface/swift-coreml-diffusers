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
    @ObservedObject var modelsViewModel: ModelsViewModel = ModelsViewModel(settings: Settings.shared)
    
    // models load up from modelsViewModel onAppear()
    @State var models: [ModelInfo] = []
    
    @State private var disclosedModel = true
    @State private var disclosedPrompt = true
    @State private var disclosedGuidance = false
    @State private var disclosedSteps = false
    @State private var disclosedSeed = false
    @State private var disclosedAdvanced = false

    // TODO: refactor download with similar code in Loading.swift (iOS)
    @State private var stateSubscriber: Cancellable?
    @State private var pipelineState: PipelineState = .downloading(0)
    @State private var pipelineLoader: PipelineLoader? = nil

    // TODO: make this computed, and observable, and easy to read
    @State private var mustShowSafetyCheckerDisclaimer = false
    @State private var mustShowModelDownloadDisclaimer = false      // When changing advanced settings

    @State private var showModelsHelp = false
    @State private var showPromptsHelp = false
    @State private var showGuidanceHelp = false
    @State private var showStepsHelp = false
    @State private var showSeedHelp = false
    @State private var showAdvancedHelp = false
    @State private var modelIdString = Settings.shared.currentModel.modelId

    /// When selected by the user, the reveal option opens a new Finder window to the models folder location
    let revealOptionString = "-- reveal --"

    // Reasonable range for the slider
    let maxSeed: UInt32 = 1000

    func updateSafetyCheckerState() {
        mustShowSafetyCheckerDisclaimer = generation.disableSafety && !Settings.shared.safetyCheckerDisclaimerShown
    }
    
    func updateComputeUnitsState() {
        Settings.shared.currentComputeUnits = generation.computeUnits
        modelDidChange(model: Settings.shared.currentModel)
    }
    
    func resetComputeUnitsState() {
        generation.computeUnits = Settings.shared.currentComputeUnits ?? ModelInfo.defaultComputeUnits
    }
    
    func modelDidChange(model: ModelInfo) {
        guard pipelineLoader?.model != model || pipelineLoader?.computeUnits != generation.computeUnits else {
            print("Reusing same model \(model) with same compute units \(generation.computeUnits)")
            return
        }

//        print("ControlsView.modelDidChange - Loading model \(model)")
        Settings.shared.currentModel = model

        pipelineLoader?.cancel()
        pipelineState = .downloading(0)
        Task.init {
            let loader = PipelineLoader(model: model, computeUnits: generation.computeUnits, maxSeed: maxSeed, modelsViewModel: modelsViewModel)
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
                    case .failed(let error):
                        pipelineState = .failed(error)
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
    
    func isModelDownloaded(_ model: ModelInfo, computeUnits: ComputeUnits? = nil) -> Bool {
        PipelineLoader(model: model, computeUnits: computeUnits ?? generation.computeUnits, modelsViewModel: modelsViewModel).ready
    }

    func modelLabel(_ model: ModelInfo) -> some View {
        let exists = model.ready(modelsFolderURL: modelsViewModel.modelsFolderURL)
        let filledCircle = Image(systemName: "circle.fill")
            .font(.caption)
            .foregroundColor(exists ? .accentColor : .secondary)
        
        let dottedCircle = Image(systemName: "circle.dotted")
            .font(.caption)
            .foregroundColor(exists ? .accentColor : .secondary)
        
        let dl = Image(systemName: "arrow.down.circle")
            .font(.caption)
            .foregroundColor(.gray)
        
//        print("Model name: \(model.humanReadableFileName)")
//        print("Model exists? \(exists)")

        return HStack {
            if model.builtin && !exists {
                dl
            } else if exists {
                filledCircle
            } else {
                dottedCircle
            }
            
            Text(model.humanReadableFileName)
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            
            Label("Generation Options", systemImage: "gearshape.2")
                .font(.headline)
                .fontWeight(.bold)
            Divider()
            
            ScrollView {
                Group {
                    DisclosureGroup(isExpanded: $disclosedModel, content: {
                        Group {
                            HStack {
                                Picker("", selection: $modelIdString) {
                                    ForEach(models, id: \.modelId) { model in
                                        modelLabel(model)
                                    }
                                    Text("Reveal in Finder…").tag(revealOptionString)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .font(.caption)
                                .onChange(of: modelIdString) { newSelection in
//                                    print("newSelection in picker: \(newSelection)")
                                    if newSelection == revealOptionString {
                                        NSWorkspace.shared.open(modelsViewModel.modelsFolderURL)
                                    }
                                    guard let model = ModelInfo.from(modelId: newSelection) else { return }
                                    modelDidChange(model: model)
                                }
                                .disabled(modelsViewModel.builtinModels.isEmpty && modelsViewModel.addonModels.isEmpty)
                            }
                            .padding()
                        }.padding(.leading, 10)

                    }, label: {
                        Text("models")

                    })
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
                        HStack {
                            Label("Prompts", systemImage: "text.quote").foregroundColor(.secondary)
                            Spacer()
                            if disclosedPrompt {
                                Button {
                                    showPromptsHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                // Or maybe use .sheet instead
                                .popover(isPresented: $showPromptsHelp, arrowEdge: .trailing) {
                                    promptsHelp($showPromptsHelp)
                                }
                            }
                        }.foregroundColor(.secondary)
                    }
                    Divider()

                    let guidanceScaleValue = generation.guidanceScale.formatted("%.1f")
                    DisclosureGroup(isExpanded: $disclosedGuidance) {
                        CompactSlider(value: $generation.guidanceScale, in: 0...20, step: 0.5) {
                            Text("Guidance Scale")
                            Spacer()
                            Text(guidanceScaleValue)
                        }.padding(.leading, 10)
                    } label: {
                        HStack {
                            Label("Guidance Scale", systemImage: "scalemass").foregroundColor(.secondary)
                            Spacer()
                            if disclosedGuidance {
                                Button {
                                    showGuidanceHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                // Or maybe use .sheet instead
                                .popover(isPresented: $showGuidanceHelp, arrowEdge: .trailing) {
                                    guidanceHelp($showGuidanceHelp)
                                }
                            } else {
                                Text(guidanceScaleValue)
                            }
                        }.foregroundColor(.secondary)
                    }

                    DisclosureGroup(isExpanded: $disclosedSteps) {
                        CompactSlider(value: $generation.steps, in: 0...150, step: 5) {
                            Text("Steps")
                            Spacer()
                            Text("\(Int(generation.steps))")
                        }.padding(.leading, 10)
                    } label: {
                        HStack {
                            Label("Step count", systemImage: "square.3.layers.3d.down.left").foregroundColor(.secondary)
                            Spacer()
                            if disclosedSteps {
                                Button {
                                    showStepsHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showStepsHelp, arrowEdge: .trailing) {
                                    stepsHelp($showStepsHelp)
                                }
                            } else {
                                Text("\(Int(generation.steps))")
                            }
                        }.foregroundColor(.secondary)
                    }
                                        
                    DisclosureGroup(isExpanded: $disclosedSeed) {
                        let sliderLabel = generation.seed < 0 ? "Random Seed" : "Seed"
                        CompactSlider(value: $generation.seed, in: -1...Double(maxSeed), step: 1) {
                            Text(sliderLabel)
                            Spacer()
                            Text("\(Int(generation.seed))")
                        }.padding(.leading, 10)
                    } label: {
                        HStack {
                            Label("Seed", systemImage: "leaf").foregroundColor(.secondary)
                            Spacer()
                            if disclosedSeed {
                                Button {
                                    showSeedHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showSeedHelp, arrowEdge: .trailing) {
                                    seedHelp($showSeedHelp)
                                }
                            } else {
                                Text("\(Int(generation.seed))")
                            }
                        }.foregroundColor(.secondary)
                    }
                    
                    if Capabilities.hasANE {
                        Divider()
                        DisclosureGroup(isExpanded: $disclosedAdvanced) {
                            HStack {
                                Picker(selection: $generation.computeUnits, label: Text("Use")) {
                                    Text("GPU").tag(ComputeUnits.cpuAndGPU)
                                    Text("Neural Engine").tag(ComputeUnits.cpuAndNeuralEngine)
                                    Text("GPU and Neural Engine").tag(ComputeUnits.all)
                                }.pickerStyle(.radioGroup).padding(.leading)
                                Spacer()
                            }
                            .onChange(of: generation.computeUnits) { units in
                                let currentModel = Settings.shared.currentModel
                                let variantDownloaded = isModelDownloaded(currentModel, computeUnits: units)
                                if variantDownloaded {
                                    updateComputeUnitsState()
                                } else {
                                    mustShowModelDownloadDisclaimer.toggle()
                                }
                            }
                            .alert("Download Required", isPresented: $mustShowModelDownloadDisclaimer, actions: {
                                Button("Cancel", role: .destructive) { resetComputeUnitsState() }
                                Button("Download", role: .cancel) { updateComputeUnitsState() }
                            }, message: {
                                Text("This setting requires the \(currentUnitsDescription()) version of the built-in \(Settings.shared.currentModel.humanReadableFileName) model.")
                            })
                        } label: {
                            HStack {
                                Label("Advanced", systemImage: "terminal").foregroundColor(.secondary)
                                Spacer()
                                if disclosedAdvanced {
                                    Button {
                                        showAdvancedHelp.toggle()
                                    } label: {
                                        Image(systemName: "info.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $showAdvancedHelp, arrowEdge: .trailing) {
                                        advancedHelp($showAdvancedHelp)
                                    }
                                }
                            }.foregroundColor(.secondary)
                        }
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
//            print(modelsViewModel.builtinModels)
//            print(modelsViewModel.addonModels)
            self.models = modelsViewModel.builtinModels + modelsViewModel.addonModels
            modelDidChange(model: Settings.shared.currentModel)
        }
    }
}
