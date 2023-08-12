//
//  ControlsView.swift
//  Diffusion-macOS
//
//  Created by Pedro Cuenca on 18/1/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import Combine
import SwiftUI
import CompactSlider
import AppKit
import StableDiffusion

/// Track a StableDiffusion Pipeline's readiness. This includes actively downloading from the internet, uncompressing the downloaded zip file, actively loading into memory, ready to use or an Error state.
enum PipelineState: Equatable {
    case unknown
    case downloading(Double)
    case uncompressing
    case loading
    case ready
    case failed(Error)

    static func ==(lhs: PipelineState, rhs: PipelineState) -> Bool {
        switch (lhs, rhs) {
        case (.downloading(let progress1), .downloading(let progress2)):
            return progress1 == progress2
        case (.uncompressing, .uncompressing),
             (.loading, .loading),
             (.unknown, .unknown),
             (.ready, .ready):
            return true
        case (.failed(let error1), .failed(let error2)):
            return error1.localizedDescription == error2.localizedDescription
        default:
            return false
        }
    }
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
    @EnvironmentObject var modelsViewModel: ModelsViewModel
    
    /// The currently selected model
    @State var selectedModelIndex: Int?
    /// The most recently  selected model, to reset the model selection back to the last selection after reveal in finder option is selected.
    @State var lastSelectedModelIndex: Int?
    @State var selectedComputeUnits: ComputeUnits = ModelInfo.defaultComputeUnits
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
                            modelSelectorContent()
                        }.padding(.leading, 10)
                    }, label: {
                        Text("Models")
                    })
   
                    Divider()
                    
                    DisclosureGroup(isExpanded: $disclosedPrompt) {
                        Group {
                            promptsContent()
                        }.padding(.leading, 10)
                    } label: {
                        promptsLabel()
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
                        previewContent()
                    } label: {
                       previewLabel()
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
                            advancedContentGroup()
                        } label: {
                            advancedContentLabel()
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
            
            StatusView(pipelineState: $pipelineState, modelsViewModel: modelsViewModel, selectedModelIndex: $selectedModelIndex, downloadButtonAction: { downloadButtonAction() })
        }
        .padding()
        .onChange(of: modelsViewModel.filteredModels) { models in
            if let firstIndex = modelsViewModel.filteredModels.firstIndex(where: { $0 == Settings.shared.currentModel }) {
                DispatchQueue.main.async {
                    lastSelectedModelIndex = selectedModelIndex
                    selectedModelIndex = firstIndex
                }
            }
            validateModelAndUnits()
        }
        .onAppear {
            if let firstIndex = modelsViewModel.filteredModels.firstIndex(where: { $0 == Settings.shared.currentModel }) {
                DispatchQueue.main.async {
                    lastSelectedModelIndex = selectedModelIndex
                    selectedModelIndex = firstIndex
                }
            }
            selectedComputeUnits = Settings.shared.currentComputeUnits
            // Validate initial values
            validateModelAndUnits()
        }
    }
    
    // MARK: Helper Functions

    fileprivate func updateSafetyCheckerState() {
        mustShowSafetyCheckerDisclaimer = generation.disableSafety && !Settings.shared.safetyCheckerDisclaimerShown
    }

  /// If the `defaultUnits` automation selection matches then this func adds an asterix (*) character  to the start of the label which indicates best choice to the user
    func computeUnitsLabel(_ units: ComputeUnits) -> String {
        let defaultComputeUnits = ModelInfo.defaultComputeUnits
        let asterix = "* "
        if (units == defaultComputeUnits) {
            return asterix + computeUnitsDescription(units: units)
        }
        return computeUnitsDescription(units: units)
    }
    
    /// The user has been presented a download dialog box and agreed to download the missing model.
    func downloadAndCommitModelAndUnitsChange() {
        if let modelIndex = selectedModelIndex {
            if let newModel = modelsViewModel.filteredModels[safe: modelIndex] {
                Settings.shared.currentModel = newModel
            }
        }
        Settings.shared.currentComputeUnits = selectedComputeUnits
        generation.computeUnits = Settings.shared.currentComputeUnits
    }
    
    /// The selected model or variant has potentially changed. Updates the list of models in the filter list associated with the selected variant. Checks that the combination is downloaded, if yes the load the pipeline.
    private func validateModelAndUnits() {
        if let modelIndex = selectedModelIndex {
            if (modelsViewModel.filteredModels.count > modelIndex) {
                guard let model = modelsViewModel.filteredModels[safe: modelIndex] else {
                    // The model index does not exist
                    return
                }
                guard pipelineLoader?.model != model || pipelineLoader?.computeUnits != selectedComputeUnits else {
                    print("Reusing same model \(modelsViewModel.filteredModels[modelIndex].humanReadableFileName) with same compute units \(computeUnitsDescription(units: selectedComputeUnits))")
                    return
                }
                // update the list of models associated with this model/variant combination
                modelsViewModel.updateFilters()
                
                // Check if the model/variant combination are present in the models folder
                let isDownloadedCombination = modelsViewModel.getModelReadiness(model).state == ModelReadinessState.ready
                Settings.shared.currentModel = model
                Settings.shared.currentComputeUnits = selectedComputeUnits
                
                pipelineState = .unknown
                if isDownloadedCombination  {
                    // The model for this variant is already downloaded. Load it up.
                    generation.computeUnits = selectedComputeUnits
                    
                    pipelineLoader?.cancel()
                    Task.init {
                        let loader = PipelineLoader(model: model, computeUnits: selectedComputeUnits, maxSeed: maxSeed, modelsViewModel: modelsViewModel)
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
                            // The model is already downloaded! Prepare the pipeline avoiding the download steps.
                            generation.pipeline = try await loader.preparePipeline()
                            pipelineState = .ready
                        } catch {
                            print("Could not load model, error: \(error)")
                            pipelineState = .failed(error)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: VIEWS
    // When the main body becomes too long compiler errors can start to emerge.
    // Extracting some views can assist the compiler in making sense of the heirarchy.
    
    func modelSelectorContent() -> some View {
        let revealOption = -1
        return HStack {
            if modelsViewModel.filteredModels.count > 0 {
                Picker("", selection: $selectedModelIndex) {
                    ForEach(0 ..< $modelsViewModel.filteredModels.count, id: \.self) { modelIndex in
                        modelLabel(modelsViewModel.filteredModels[modelIndex]).tag(modelIndex as Int?)
                    }
                    Text("Reveal in Finder…").tag(revealOption)
                    Text("No Model Selected").tag(nil as Int?)
                }
                .id(UUID())
                .pickerStyle(MenuPickerStyle())
                .font(.caption)
                .onChange(of: selectedModelIndex) { selection in
                    guard selection != revealOption else {
                        NSWorkspace.shared.open(modelsViewModel.modelsFolderURL)
                        // restore last selected model after opening Finder folder
                        DispatchQueue.main.async {
                            selectedModelIndex = lastSelectedModelIndex
                        }
                        return
                    }
                    validateModelAndUnits()
                }
                .disabled(modelsViewModel.filteredBuiltinModels.isEmpty && modelsViewModel.filteredAddonModels.isEmpty)
            }
            
            Button {
                // Set the central singleton instance to ensure that the info panel state can be updated from anywhere in the app
                Settings.shared.isShowingImportPanel = true
            } label: {
                Image(systemName: "plus").foregroundColor(.gray)
            }
            .font(.caption)
            .modifier(ImportModelBehavior(modelsViewModel: modelsViewModel))
            .onAppear {
                NSApp.keyWindow?.standardWindowButton(.closeButton)?.isHidden = true
                NSApp.keyWindow?.standardWindowButton(.miniaturizeButton)?.isHidden = true
                NSApp.keyWindow?.standardWindowButton(.zoomButton)?.isHidden = true
            }
            .onDisappear {
                NSApp.keyWindow?.standardWindowButton(.closeButton)?.isHidden = false
                NSApp.keyWindow?.standardWindowButton(.miniaturizeButton)?.isHidden = false
                NSApp.keyWindow?.standardWindowButton(.zoomButton)?.isHidden = false
            }
            .keyboardShortcut("I", modifiers: [.command, .shift])
        }
    }
  
    /// A SwiftUI View for presenting the two `PromptTextField` controls for positive and negative prompts.
    private func promptsContent() -> some View {
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
        .environmentObject(modelsViewModel)
    }
    
    private func promptsLabel() -> some View {
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
                // Or maybe use .sheet instead --pcuenca
                .popover(isPresented: $showPromptsHelp, arrowEdge: .trailing) {
                    promptsHelp($showPromptsHelp)
                }
            }
        }.foregroundColor(.secondary)
    }
    
    private func previewContent() -> some View {
        CompactSlider(value: $generation.previews, in: 0...25, step: 1) {
            Text("Previews")
            Spacer()
            Text("\(Int(generation.previews))")
        }.padding(.leading, 10)
    }
    
    private func previewLabel() -> some View {
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
    
    private func advancedContentGroup() -> some View {
        return HStack {
            Picker(selection: $selectedComputeUnits, label: Text("Use")) {
                Text(computeUnitsLabel(ComputeUnits.cpuAndGPU)).tag(ComputeUnits.cpuAndGPU)
                Text(computeUnitsLabel(ComputeUnits.cpuAndNeuralEngine)).tag(ComputeUnits.cpuAndNeuralEngine)
                Text(computeUnitsLabel(ComputeUnits.all)).tag(ComputeUnits.all)
            }.pickerStyle(.radioGroup).padding(.leading)
            Spacer()
        }
        .onChange(of: selectedComputeUnits) { units in
            validateModelAndUnits()
        }
    }
    
    private func advancedContentLabel() -> some View {
        return HStack {
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
    
    fileprivate func modelLabel(_ model: ModelInfo) -> some View {
        let exists = modelsViewModel.getModelReadiness(model).state == ModelReadinessState.ready
        let filledCircle = Image(systemName: "circle.fill")
            .font(.caption)
            .foregroundColor(exists ? .accentColor : .secondary)
        
        let dottedCircle = Image(systemName: "circle.dotted")
            .font(.caption)
            .foregroundColor(exists ? .accentColor : .secondary)
        
        let dl = Image(systemName: "arrow.down.circle")
            .font(.caption)
            .foregroundColor(.gray)
        
        
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

    // When the download button is pressed start downloading the selected model/variant combination
    private func downloadButtonAction() {
        pipelineState = .downloading(0.0)
        pipelineLoader?.state = .downloading(0.0)
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
