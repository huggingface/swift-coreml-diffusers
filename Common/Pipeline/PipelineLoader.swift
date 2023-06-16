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

class PipelineLoader {
    
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
        if ready {
            state = .readyOnDisk
            return
        }
        if downloaded {
            state = .downloaded
            return
        }
        state = .waitingToDownload
    }
}

extension PipelineLoader {
    func cancel() { downloader?.cancel() }
}

extension PipelineLoader {
    var url: URL {
        return model.modelURL(for: variant)
    }
    
    var zipFilename: String {
        return url.lastPathComponent
    }
    
    var downloadedURL: URL {
//        print("downloadedURL: \(modelsViewModel.modelsFolderURL.appending(path: zipFilename))")
        return modelsViewModel.modelsFolderURL.appending(path: zipFilename)  }

    var uncompressURL: URL {
//        print("uncompressURL: \(modelsViewModel.modelsFolderURL)")
        return modelsViewModel.modelsFolderURL
        }
    
    var packagesFilename: String {
//        print("packagesFilename: \(downloadedURL.deletingPathExtension().lastPathComponent)")
        return downloadedURL.deletingPathExtension().lastPathComponent
        }

    var compiledURL: URL {
//        print("compiledURL: \(modelsViewModel.modelsFolderURL.appending(path: packagesFilename))")
        return modelsViewModel.modelsFolderURL.appending(path: packagesFilename)
    }

    var downloaded: Bool {
//        print("file downloaded to \(downloadedURL.path)? \(FileManager.default.fileExists(atPath: downloadedURL.path))")
        return FileManager.default.fileExists(atPath: downloadedURL.path)
    }
    
    var ready: Bool {
//        print("file ready at \(compiledURL.path)? \(FileManager.default.fileExists(atPath: compiledURL.path))")
        return  FileManager.default.fileExists(atPath: compiledURL.path)
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
    func prepare() async throws -> Pipeline {
        do {
            try await download()
            try await unzip()
            let pipeline = try await load(url: compiledURL)
            return Pipeline(pipeline, maxSeed: maxSeed)
        } catch {
            state = .failed(error)
            throw error
        }
    }
    
    @discardableResult
    func download() async throws -> URL {
        if ready || downloaded { return downloadedURL }
        
        let downloader = Downloader(from: url, to: downloadedURL)
        self.downloader = downloader
        downloadSubscriber = downloader.downloadState.sink { state in
            if case .downloading(let progress) = state {
                self.state = .downloading(progress)
            }
        }
        try downloader.waitUntilDone()
        return downloadedURL
    }
    
    func unzip() async throws {
        guard downloaded else { return }
        state = .uncompressing
        do {
            try FileManager().unzipItem(at: downloadedURL, to: uncompressURL)
        } catch {
            // Cleanup if error occurs while unzipping
            try FileManager.default.removeItem(at:(uncompressURL.appending(path: packagesFilename)))
            throw error
        }
        try FileManager.default.removeItem(at: downloadedURL)
        state = .readyOnDisk
    }
    
    func load(url: URL) async throws -> StableDiffusionPipeline {
        let beginDate = Date()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let pipeline = try StableDiffusionPipeline(resourcesAt: url,
                                                   controlNet: [],
                                                   configuration: configuration,
                                                   disableSafety: false,
                                                   reduceMemory: model.reduceMemory)
        try pipeline.loadResources()
        print("Pipeline loaded in \(Date().timeIntervalSince(beginDate))")
        state = .loaded
        return pipeline
    }
}
