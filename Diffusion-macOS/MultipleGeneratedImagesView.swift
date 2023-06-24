//
//  MultipleGeneratedImagesView.swift
//  Diffusion-macOS
//
//  Created by Dolmere on 14/06/2023.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import UniformTypeIdentifiers

struct MultipleGeneratedImagesView: View {
    
    @State var generatedImages: [DiffusionImage?]
    @State private var gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 3)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: gridColumns) {
                    ForEach(generatedImages, id:\.self) { genImage in
                        if let diffusionImage = genImage {
                            SingleGeneratedImageView(generatedImage: diffusionImage)
                        } else {
                            AnyView(Text("Missing image!"))
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity) // Ensure the grid occupies full width
            }
            .frame(width: geometry.size.width, height: geometry.size.height) // Match parent size
        }
    }
}
