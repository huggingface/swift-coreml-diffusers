//
//  PromptTextField.swift
//  Diffusion-macOS
//
//  Created by Dolmere on 22/06/2023.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import Combine
import StableDiffusion

struct PromptTextField: View {
    @State private var output: String = ""
    @State private var input: String = ""
    @State private var typing = false
    @State private var tokenCount: Int = 0
    @State var isPositivePrompt: Bool = true
    @State private var tokenizer: BPETokenizer?
    @State private var currentModelVersion: String = ""

    @Binding var textBinding: String
    @Binding var model: String // the model version as it's stored in Settings

    private let maxTokenCount = 77

    private var modelInfo: ModelInfo? {
        ModelInfo.from(modelVersion: $model.wrappedValue)
    }
    
    private var filename: String? {
        let variant = modelInfo?.bestAttention ?? .original
        return modelInfo?.modelURL(for: variant).lastPathComponent
    }
    
    private var downloadedURL: URL? {
        if let filename = filename {
            return PipelineLoader.models.appendingPathComponent(filename)
        }
        return nil
    }
    
    private var packagesFilename: String? {
        (filename as NSString?)?.deletingPathExtension
    }
    
    private var compiledURL: URL? {
        if let packagesFilename = packagesFilename {
            return downloadedURL?.deletingLastPathComponent().appendingPathComponent(packagesFilename)
        }
        return nil
    }
    
    private var textColor: Color {
        switch tokenCount {
        case 0...65:
            return .green
        case 66...75:
            return .orange
        default:
            return .red
        }
    }
    
    // macOS initializer
    init(text: Binding<String>, isPositivePrompt: Bool, model: Binding<String>) {
         _textBinding = text
         self.isPositivePrompt = isPositivePrompt
        _model = model
    }
    
    // iOS initializer
    init(text: Binding<String>, isPositivePrompt: Bool, model: String) {
        _textBinding = text
        self.isPositivePrompt = isPositivePrompt
        _model = .constant(model)
    }

    var body: some View {
        VStack {
            #if os(macOS)
            TextField(isPositivePrompt ? "Positive prompt" : "Negative Prompt", text: $textBinding,
                      axis: .vertical)
                .lineLimit(20)
                .textFieldStyle(.squareBorder)
                .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: 20))
                .foregroundColor(textColor == .green ? .primary : textColor)
                .frame(minHeight: 30)
            if modelInfo != nil && tokenizer != nil {
                HStack {
                    Spacer()
                    if !textBinding.isEmpty {
                        Text("\(tokenCount)")
                            .foregroundColor(textColor)
                        Text(" / \(maxTokenCount)")
                    }
                }
                .onReceive(Just(textBinding)) { text in
                    updateTokenCount(newText: text)
                }
                .font(.caption)
            }
            #else
            TextField("Prompt", text: $textBinding, axis: .vertical)
                .lineLimit(20)
                .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: 20))
                .foregroundColor(textColor == .green ? .primary : textColor)
                .frame(minHeight: 30)
            HStack {
                if !textBinding.isEmpty {
                    Text("\(tokenCount)")
                        .foregroundColor(textColor)
                    Text(" / \(maxTokenCount)")
                }
                Spacer()
            }
            .onReceive(Just(textBinding)) { text in
                updateTokenCount(newText: text)
            }
            .font(.caption)
            #endif
        }
        .onChange(of: model) { model in
            updateTokenCount(newText: textBinding)
        }
    }

    private func updateTokenCount(newText: String) {
        // ensure that the compiled URL exists
        guard let compiledURL = compiledURL else { return }
        // Initialize the tokenizer only when it's not created yet or the model changes
        // Check if the model version has changed
        let modelVersion = $model.wrappedValue
        if modelVersion != currentModelVersion {
            do {
                tokenizer = try BPETokenizer(
                    mergesAt: compiledURL.appendingPathComponent("merges.txt"),
                    vocabularyAt: compiledURL.appendingPathComponent("vocab.json")
                )
                currentModelVersion = modelVersion
            } catch {
                print("Failed to create tokenizer: \(error)")
                return
            }
        }
        let (tokens, _) = tokenizer?.tokenize(input: newText) ?? ([], [])

        DispatchQueue.main.async {
            self.tokenCount = tokens.count
        }
    }
}
