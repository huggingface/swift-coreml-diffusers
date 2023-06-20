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
import AppKit
import StableDiffusion

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
    @State var selectedModelIndex: Int = 0
    @State var selectedComputeUnits: ComputeUnits = ModelInfo.defaultComputeUnits
    
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
    
    @State private var showModelsHelp = false
    @State private var showPromptsHelp = false
    @State private var showGuidanceHelp = false
    @State private var showStepsHelp = false
    @State private var showSeedHelp = false
    @State private var showAdvancedHelp = false
        
    // Reasonable range for the slider
    let maxSeed: UInt32 = 1000
    
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
                            disclosedModelContent()
                        }.padding(.leading, 10)
                    }, label: {
                        Text("models")
                    })
                    Divider()
                    
                    DisclosureGroup(isExpanded: $disclosedPrompt) {
                        Group {
                            disclosedModelLabel()
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
                                // Or maybe use .sheet instead --pcuenca
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
                selectedModelIndex = firstIndex
            }
            validateModelAndUnits()
        }
        .onAppear {
            if let firstIndex = modelsViewModel.filteredModels.firstIndex(where: { $0 == Settings.shared.currentModel }) {
                selectedModelIndex = firstIndex
            }
            selectedComputeUnits = Settings.shared.currentComputeUnits
            // Validate initial values
            validateModelAndUnits()
        }
    }
    
    // -- Helper Function --
    
    func updateSafetyCheckerState() {
        mustShowSafetyCheckerDisclaimer = generation.disableSafety && !Settings.shared.safetyCheckerDisclaimerShown
    }
    
    func computeUnitsLabel(_ units: ComputeUnits) -> String {
        // If the defaultUnits automation selection matches add an asterix to the start of the label to indicate best choice to the user
        let defaultComputeUnits = ModelInfo.defaultComputeUnits
        let asterix = "* "
        if (units == defaultComputeUnits) {
            return asterix + computeUnitsDescription(units: units)
        }
        return computeUnitsDescription(units: units)
    }
    
    // The user has been presented a download dialog box and agreed to download the missing model.
    func downloadAndCommitModelAndUnitsChange() {
        Settings.shared.currentModel = modelsViewModel.filteredModels[selectedModelIndex]
        Settings.shared.currentComputeUnits = selectedComputeUnits
        generation.computeUnits = Settings.shared.currentComputeUnits
    }
    
    
    private func validateModelAndUnits() {
        if (modelsViewModel.filteredModels.count > selectedModelIndex) {
            let model = modelsViewModel.filteredModels[selectedModelIndex]
            guard pipelineLoader?.model != model || pipelineLoader?.computeUnits != selectedComputeUnits else {
                print("Reusing same model \(modelsViewModel.filteredModels[selectedModelIndex].humanReadableFileName) with same compute units \(computeUnitsDescription(units: selectedComputeUnits))")
                return
            }
            // update the list of models associated with this model/variant combination
            modelsViewModel.updateFilters()
            
            //            print("CONTROL VIEW validateModelAndUnits GETTING MODEL READY")
            // Check if the model/variant combination are present in the models folder
            let isDownloadedCombination = modelsViewModel.getModelReadiness(model).state == ModelReadinessState.ready
            Settings.shared.currentModel = model
            Settings.shared.currentComputeUnits = selectedComputeUnits
            
            //            print("is model downloaded in this combination? \(isDownloadedCombination)")
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
                        // Prepare the pipeline avoiding the download steps since the model is already downloaded!
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
    
    // --VIEWS --
    //When the main body becomes too long off compiler errors can start to emerge.
    //Extracting some views can assist the compiler in making sense of the heirarchy.
    
    func disclosedModelContent() -> some View {
        return HStack {
            Picker("", selection: $selectedModelIndex) {
                ForEach(0 ..< $modelsViewModel.filteredModels.count, id: \.self) { modelIndex in
                    modelLabel(modelsViewModel.filteredModels[modelIndex]).tag(modelIndex)
                }
            }
            .id(UUID())
            .pickerStyle(MenuPickerStyle())
            .font(.caption)
            .onChange(of: selectedModelIndex) { _ in
                validateModelAndUnits()
            }
            .disabled(modelsViewModel.filteredBuiltinModels.isEmpty && modelsViewModel.filteredAddonModels.isEmpty)

            Button {
                NSWorkspace.shared.open(modelsViewModel.modelsFolderURL)
            } label: {
                Image(systemName: "folder").foregroundColor(.gray)
            }
            .font(.caption)

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
        //            .padding()
    }
    
    
    func disclosedModelLabel() -> some View {
        return VStack {

            TextField("Positive prompt", text: $generation.positivePrompt,
                      axis: .vertical)
                .lineLimit(5)
                .textFieldStyle(.squareBorder)
                .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: 20))
            
            TextField("Negative prompt", text: $generation.negativePrompt,
                      axis: .vertical).lineLimit(5)
                .textFieldStyle(.squareBorder)
        }
    }
    
    func advancedContentGroup() -> some View {
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
    
    func advancedContentLabel() -> some View {
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
    
    // When the download button is pressed start downloading the selected model/variant combination
    func downloadButtonAction() {
        print("download button action pressed")
        pipelineState = .downloading(0.0)
        pipelineLoader?.state = .downloading(0.0)
    }

    func modelLabel(_ model: ModelInfo) -> some View {
//            print("CONTROLS VIEW MODEL LABEL GETTING MODEL.READY")
        let exists = modelsViewModel.getModelReadiness(model).state == ModelReadinessState.ready
        
//            print("Model name: \(model.humanReadableFileName) variant: \(model.variant)")
//            print("Model exists? \(exists)")
        
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

}
