//
//  ContentView.swift
//  Diffusion-macOS
//
//  Created by Cyril Zakka on 1/12/23.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            PromptView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            Image("placeholder")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 400, height: 400)
                .cornerRadius(15)
                .toolbar {
                    Button(action: {}) {
                                Label("share", systemImage: "square.and.arrow.up")
                            }
                        }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
