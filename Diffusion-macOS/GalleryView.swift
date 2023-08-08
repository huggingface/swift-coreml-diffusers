//
//  GalleryView.swift
//  Diffusion
//
//  Created by Pedro Cuenca on 18/1/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var generation: GenerationContext
    @EnvironmentObject var imageViewModel: ImageViewObservableModel
    private var gridColumns: [GridItem] {
        // Layout the grid based on the desired number of images being generated
        let imageCount = imageViewModel.imageCount
        if imageCount == 1 {
            return [GridItem()]
        } else if imageCount == 2 {
            return [GridItem(), GridItem()]
        } else {
            return [GridItem(), GridItem(), GridItem()]
        }
    }

    var body: some View {
        
        ScrollView {
            VStack(spacing: 5) {
                LazyVGrid(columns: gridColumns, spacing: 5) {
                    if imageViewModel.currentBuildImages.isEmpty {
                        AnyView(
                            Image("placeholder")
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                        )
                    } else {
                        ForEach(0..<imageViewModel.imageCount, id:\.self) { index in
                            if index < imageViewModel.currentBuildImages.count {
                                GeneratedImageView(diffusionImageIndex: index)
                                    .environmentObject(generation)
                                    .aspectRatio(contentMode: .fit)
                            }
                        }
                    }
                }
            }
        }
    }
}
