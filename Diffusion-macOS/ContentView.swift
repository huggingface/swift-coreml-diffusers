//
//  ContentView.swift
//  Diffusion-macOS
//
//  Created by Cyril Zakka on 1/12/23.
//

import SwiftUI

struct ContentView: View {
    @StateObject var context = GenerationContext()

    var body: some View {
        NavigationSplitView {
            PromptView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            GeneratedImageView()
                .aspectRatio(contentMode: .fit)
                .frame(width: 512, height: 512)
                .cornerRadius(15)
                .toolbar {
                    Button(action: {}) {
                        Label("share", systemImage: "square.and.arrow.up")
                    }
                }

        }
        .environmentObject(context)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
