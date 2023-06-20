//
//  ContentView.swift
//  Diffusion-macOS
//
//  Created by Cyril Zakka on 1/12/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import ImageIO

struct ContentView: View {
    @StateObject var generation = GenerationContext()
    @StateObject var modelsViewModel: ModelsViewModel = ModelsViewModel(settings: Settings.shared)

    func toolbar() -> any View {
        if case .complete(let prompt, let cgImage, _, _) = generation.state, let cgImage = cgImage {
            // TODO: share seed too
            return ShareButtons(image: cgImage, name: prompt)
        } else {
            let prompt = DEFAULT_PROMPT
            let cgImage = NSImage(imageLiteralResourceName: "placeholder").cgImage(forProposedRect: nil, context: nil, hints: nil)!
            return ShareButtons(image: cgImage, name: prompt)
        }
    }
    
    var body: some View {
        NavigationSplitView {
            ControlsView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            GeneratedImageView()
                .aspectRatio(contentMode: .fit)
                .frame(width: 512, height: 512)
                .cornerRadius(15)
                .toolbar {
                    AnyView(toolbar())
                }

        }
        .environmentObject(generation)
        .environmentObject(modelsViewModel)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
