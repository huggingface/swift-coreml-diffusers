//
//  ContentView.swift
//  Diffusion-macOS
//
//  Created by Cyril Zakka on 1/12/23.
//

import SwiftUI

struct ContentView: View {
    @StateObject var generation = GenerationContext()

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
                    if case .complete(let prompt, let cgImage, _) = generation.state, let cgImage = cgImage {
                        let image = Image(cgImage, scale: 1, label: Text(prompt))
                        ShareLink(prompt, item: image, preview: SharePreview(prompt, image: image))
                    } else {
                        let prompt = DEFAULT_PROMPT
                        let image = Image("placeholder")
                        ShareLink(prompt, item: image, preview: SharePreview(prompt, image: image))
                    }
                }

        }
        .environmentObject(generation)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
