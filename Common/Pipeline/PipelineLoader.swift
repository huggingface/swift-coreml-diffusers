//
//  PipelineLoader.swift
//  Diffusion
//
//  Created by Pedro Cuenca on December 2022.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import CoreML
import Combine
import ZIPFoundation
import StableDiffusion

//TODO: Separate download from Pipeline completely. Downloading of models should be its own separate concern. -- dolmere
class PipelineLoader: ObservableObject {

    let model: ModelInfo
    let computeUnits: ComputeUnits
    let maxSeed: UInt32
    let modelsViewModel: ModelsViewModel
    
    private var downloadSubscriber: Cancellable?


    init(model: ModelInfo, computeUnits: ComputeUnits? = nil, maxSeed: UInt32 = UInt32.max, modelsViewModel: ModelsViewModel) {
        self.model = model
        self.computeUnits = computeUnits ?? model.defaultComputeUnits
        self.maxSeed = maxSeed
        self.modelsViewModel = modelsViewModel
        state = .undetermined
        setInitialState()
    }
        
    enum PipelinePreparationPhase {
        case undetermined
        case waitingToDownload
        case downloading(Double)
        case downloaded
        case uncompressing
        case readyOnDisk
        case loaded
        case failed(Error)
    }
    
    var state: PipelinePreparationPhase {
        didSet {
            statePublisher.value = state
        }
    }
    private(set) lazy var statePublisher: CurrentValueSubject<PipelinePreparationPhase, Never> = CurrentValueSubject(state)
    private(set) var downloader: Downloader? = nil

    func setInitialState() {
//        print("PIPLINE SET INITIAL STATE GETTING MODEL.READY")
        // Downloaded built-in variants and all 3rd party models should be found and set to readyOnDisk
        if modelsViewModel.getModelReadiness(model).state == ModelReadinessState.ready {
//            print("model is ready on disk")
            state = .readyOnDisk
            return
        }
        // Built-in variants that have been downloaded but not uncompressed should be caught here
        if downloaded {
            state = .downloaded
            modelsViewModel.setModelReadiness(of: model, to: ModelReadinessState.downloaded)
            return
        }
        // Built-in models that are missing should be caught here
        state = .waitingToDownload
        modelsViewModel.setModelReadiness(of: model, to: ModelReadinessState.unknown)
    }
}

extension PipelineLoader {
    func cancel() { downloader?.cancel() }
}

extension PipelineLoader {
    var url: URL {
        // Built-in models have their own URL builder function
        if model.builtin {
            return model.modelURL(for: variant)
        }
        // 3rd party models are local only
        return modelsViewModel.modelsFolderURL.appending(path: model.fileSystemFileName)
    }
    
    var zipFilename: String {
        return url.lastPathComponent
    }
    
    var downloadedURL: URL {
        return modelsViewModel.modelsFolderURL.appending(path: zipFilename)  }

    var uncompressURL: URL {
        return modelsViewModel.modelsFolderURL
        }
    
    var packagesFilename: String {
        return downloadedURL.deletingPathExtension().lastPathComponent
        }

    var compiledURL: URL {
        return modelsViewModel.modelsFolderURL.appending(path: packagesFilename)
    }

    var downloaded: Bool {
        return FileManager.default.fileExists(atPath: downloadedURL.path)
    }
    
    var variant: AttentionVariant {
        switch computeUnits {
        case .cpuOnly           : return .original          // Not supported yet
        case .cpuAndGPU         : return .original
        case .cpuAndNeuralEngine: return model.supportsAttentionV2 ? .splitEinsumV2 : .splitEinsum
        case .all               : return .splitEinsum
        @unknown default:
            fatalError("Unknown MLComputeUnits")
        }
    }
    
    // TODO: maybe receive Progress to add another progress as child -- pcuena
    func preparePipeline() async throws -> Pipeline {
        do {
            let pipeline = try await load(url: modelsViewModel.modelsFolderURL.appendingPathComponent(model.fileSystemFileName))
            return Pipeline(pipeline, maxSeed: maxSeed)
        } catch {
            state = .failed(error)
            throw error
        }
    }
    
    func prepareDownload() async throws -> Pipeline {
        do {
            try await download()
            try await unzip()
            return try await preparePipeline()
        } catch {
            state = .failed(error)
            throw error
        }
    }
    
    @discardableResult
    func download() async throws -> URL {
        if modelsViewModel.getModelReadiness(model).state == ModelReadinessState.ready || downloaded { return downloadedURL }
        let downloader = Downloader(from: url, to: downloadedURL)
        self.downloader = downloader
        downloadSubscriber = downloader.downloadState.sink { state in
            if case .downloading(let progress) = state {
                self.state = .downloading(progress)
                self.modelsViewModel.setModelReadiness(of: self.model, to: .downloading)
            }
        }
        try downloader.waitUntilDone()
        return downloadedURL
    }
    
    func unzip() async throws {
        guard downloaded else { return }
        state = .uncompressing
        modelsViewModel.setModelReadiness(of: model, to: .uncompressing)
        do {
            try FileManager().unzipItem(at: downloadedURL, to: uncompressURL)
        } catch {
            // Cleanup if error occurs while unzipping
            try FileManager.default.removeItem(at:(uncompressURL.appending(path: packagesFilename)))
            throw error
        }
        try FileManager.default.removeItem(at: downloadedURL)
        state = .readyOnDisk
        modelsViewModel.setModelReadiness(of: model, to: .ready)
    }
    
    func load(url: URL) async throws -> StableDiffusionPipelineProtocol {
        let beginDate = Date()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let pipeline: StableDiffusionPipelineProtocol
        if model.isXL {
            if #available(macOS 14.0, iOS 17.0, *) {
                pipeline = try StableDiffusionXLPipeline(resourcesAt: url,
                                                       configuration: configuration,
                                                       reduceMemory: model.reduceMemory)
            } else {
                throw "Stable Diffusion XL requires macOS 14"
            }
        } else {
            pipeline = try StableDiffusionPipeline(resourcesAt: url,
                                                       controlNet: [],
                                                       configuration: configuration,
                                                       disableSafety: false,
                                                       reduceMemory: model.reduceMemory)
        }
        try pipeline.loadResources()
        print("Pipeline loaded in \(Date().timeIntervalSince(beginDate))")
        state = .loaded
        modelsViewModel.setModelReadiness(of: model, to: ModelReadinessState.ready)
        return pipeline
    }
}
