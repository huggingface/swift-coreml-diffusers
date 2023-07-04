//
//  InfoPanel.swift
//  Diffusion-macOS
//
//  Created by Dolmere on 03/07/2023.
//

import SwiftUI

struct InfoPanel: View {
    @Binding var isShowingInfo: Bool
    let diffusionImage: DiffusionImage?
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                
                Button(action: {
                    isShowingInfo.toggle()
                }) {
                    Text("Close")
                }
                .font(.subheadline)
                .foregroundColor(.primary)
//                .background(.blue)
                .padding()
                .buttonStyle(.borderedProminent)
            }
            if let diffusionImage = diffusionImage {
                Image(nsImage: NSImage(cgImage: diffusionImage.cgImage, size: CGSize(width: diffusionImage.cgImage.width, height: diffusionImage.cgImage.height)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                Spacer()
                // TODO: turn 'recipe' config information into button to setup new run from selected image.
                Text("Positive Prompt: \(diffusionImage.positivePrompt)")
                Text("Negative Prompt: \(diffusionImage.negativePrompt)")
                Text("Guidance Scale: \(Int(diffusionImage.guidanceScale))")
                Text("Step Count: \(Int(diffusionImage.steps))")
                Text("Seed: \(Int(diffusionImage.seed))")
            }
        }
        .padding()

    }
}
