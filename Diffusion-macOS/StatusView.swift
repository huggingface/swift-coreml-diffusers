//
//  StatusView.swift
//  Diffusion-macOS
//
//  Created by Cyril Zakka on 1/12/23.
//

import SwiftUI

struct StatusView: View {
    var pipelineState: Binding<PipelineState>
    
    var body: some View {
        switch pipelineState.wrappedValue {
        case .downloading(let progress):
            ProgressView("Downloading…", value: progress*100, total: 110).padding()
        case .uncompressing:
            ProgressView("Uncompressing…", value: 100, total: 110).padding()
        case .loading:
            ProgressView("Loading…", value: 105, total: 110).padding()
        case .ready:
            Button {
                // Generate image here
            } label: {
                Text("Generate")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
        case .failed:
            Text("Pipeline loading error")
        }
    }
}

struct StatusView_Previews: PreviewProvider {
    static var previews: some View {
        StatusView(pipelineState: .constant(.downloading(0.2)))
    }
}
