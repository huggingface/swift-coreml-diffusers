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

/// Track a StableDiffusion Pipeline's readiness. This include actively downloading from the internet, uncompressing the downloaded zip file, actively loading into memory, ready to use or an Error state.
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

    static let models = ModelInfo.BUILTIN_MODELS
    
    @State private var model = Settings.shared.currentModel.modelVersion
    @State private var disclosedModel = true
    @State private var disclosedPrompt = true
    @State private var disclosedGuidance = false
    @State private var disclosedSteps = false
    @State private var disclosedPreview = false
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
    @State private var showPreviewHelp = false
    @State private var showSeedHelp = false
    @State private var showAdvancedHelp = false
    @State private var positiveTokenCount: Int = 0
    @State private var negativeTokenCount: Int = 0

    let maxSeed: UInt32 = UInt32.max
    private var textFieldLabelSeed: String { generation.seed < 1 ? "Random Seed" : "Seed" }
    
    var modelFilename: String? {
        guard let pipelineLoader = pipelineLoader else { return nil }
        let selectedURL = pipelineLoader.compiledURL
        guard FileManager.default.fileExists(atPath: selectedURL.path) else { return nil }
        return selectedURL.path
    }
    
    fileprivate func updateSafetyCheckerState() {
        mustShowSafetyCheckerDisclaimer = generation.disableSafety && !Settings.shared.safetyCheckerDisclaimerShown
    }
    
    fileprivate func updateComputeUnitsState() {
        Settings.shared.userSelectedComputeUnits = generation.computeUnits
        modelDidChange(model: Settings.shared.currentModel)
    }
    
    fileprivate func resetComputeUnitsState() {
        generation.computeUnits = Settings.shared.userSelectedComputeUnits ?? ModelInfo.defaultComputeUnits
    }

    fileprivate func modelDidChange(model: ModelInfo) {
        guard pipelineLoader?.model != model || pipelineLoader?.computeUnits != generation.computeUnits else {
            print("Reusing same model \(model) with units \(generation.computeUnits)")
            return
        }

        Settings.shared.currentModel = model

        pipelineLoader?.cancel()
        pipelineState = .downloading(0)
        Task.init {
            let loader = PipelineLoader(model: model, computeUnits: generation.computeUnits, maxSeed: maxSeed)
            self.pipelineLoader = loader
            stateSubscriber = loader.statePublisher.sink { state in
                DispatchQueue.main.async {
                    switch state {
                    case .downloading(let progress):
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
    
    fileprivate func isModelDownloaded(_ model: ModelInfo, computeUnits: ComputeUnits? = nil) -> Bool {
        PipelineLoader(model: model, computeUnits: computeUnits ?? generation.computeUnits).ready
    }
    
    fileprivate func modelLabel(_ model: ModelInfo) -> Text {
        let downloaded = isModelDownloaded(model)
        let prefix = downloaded ? "● " : "◌ "  //"○ "
        return Text(prefix).foregroundColor(downloaded ? .accentColor : .secondary) + Text(model.modelVersion)
    }
    
    fileprivate func prompts() -> some View {
        VStack {
            Spacer()
            PromptTextField(text: $generation.positivePrompt, isPositivePrompt: true, model: $model)
                .padding(.top, 5)
            Spacer()
            PromptTextField(text: $generation.negativePrompt, isPositivePrompt: false, model: $model)
                .padding(.bottom, 5)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            
            Label("Generation Options", systemImage: "gearshape.2")
                .font(.headline)
                .fontWeight(.bold)
            Divider()
            
            ScrollView {
                Group {
                    DisclosureGroup(isExpanded: $disclosedModel) {
                        let revealOption = "-- reveal --"
                        Picker("", selection: $model) {
                            ForEach(Self.models, id: \.modelVersion) {
                                modelLabel($0)
                            }
                            Text("Reveal in Finder…").tag(revealOption)
                        }
                        .onChange(of: model) { selection in
                            guard selection != revealOption else {
                                // The reveal option has been requested - open the models folder in Finder
                                NSWorkspace.shared.selectFile(modelFilename, inFileViewerRootedAtPath: PipelineLoader.models.path)
                                model = Settings.shared.currentModel.modelVersion
                                return
                            }
                            guard let model = ModelInfo.from(modelVersion: selection) else { return }
                            modelDidChange(model: model)
                        }
                    } label: {
                        HStack {
                            Label("Model from Hub", systemImage: "cpu").foregroundColor(.secondary)
                            Spacer()
                            if disclosedModel {
                                Button {
                                    showModelsHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                // Or maybe use .sheet instead
                                .sheet(isPresented: $showModelsHelp) {
                                    modelsHelp($showModelsHelp)
                                }
                            }
                        }.foregroundColor(.secondary)
                    }
                    Divider()
                    
                    DisclosureGroup(isExpanded: $disclosedPrompt) {
                        Group {
                            prompts()
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
                        CompactSlider(value: $generation.steps, in: 1...150, step: 1) {
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

                    DisclosureGroup(isExpanded: $disclosedPreview) {
                        CompactSlider(value: $generation.previews, in: 0...25, step: 1) {
                            Text("Previews")
                            Spacer()
                            Text("\(Int(generation.previews))")
                        }.padding(.leading, 10)
                    } label: {
                        HStack {
                            Label("Preview count", systemImage: "eye.square").foregroundColor(.secondary)
                            Spacer()
                            if disclosedPreview {
                                Button {
                                    showPreviewHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showPreviewHelp, arrowEdge: .trailing) {
                                    previewHelp($showPreviewHelp)
                                }
                            } else {
                                Text("\(Int(generation.previews))")
                            }
                        }.foregroundColor(.secondary)
                    }

                    DisclosureGroup(isExpanded: $disclosedSeed) {
                        discloseSeedContent()
                            .padding(.leading, 10)
                    } label: {
                        HStack {
                            Label(textFieldLabelSeed, systemImage: "leaf").foregroundColor(.secondary)
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
                        }
                        .foregroundColor(.secondary)
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
                                guard let currentModel = ModelInfo.from(modelVersion: model) else { return }
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
                                Text("This setting requires a new version of the selected model.")
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
            modelDidChange(model: ModelInfo.from(modelVersion: model) ?? ModelInfo.v2Base)
        }
    }
    
    fileprivate func discloseSeedContent() -> some View {
        let seedBinding = Binding<String>(
            get: {
                String(generation.seed)
            },
            set: { newValue in
                if let seed = UInt32(newValue) {
                    generation.seed = seed
                } else {
                    generation.seed = 0
                }
            }
        )
        
        return HStack {
            TextField("", text: seedBinding)
                .multilineTextAlignment(.trailing)
                .onChange(of: seedBinding.wrappedValue, perform: { newValue in
                    if let seed = UInt32(newValue) {
                        generation.seed = seed
                    } else {
                        generation.seed = 0
                    }
                })
                .onReceive(Just(seedBinding.wrappedValue)) { newValue in
                    let filtered = newValue.filter { "0123456789".contains($0) }
                    if filtered != newValue {
                        seedBinding.wrappedValue = filtered
                    }
                }
            Stepper("", value: $generation.seed, in: 0...UInt32.max)
        }
    }
}
