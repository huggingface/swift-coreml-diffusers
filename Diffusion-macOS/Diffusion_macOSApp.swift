//
//  Diffusion_macOSApp.swift
//  Diffusion-macOS
//
//  Created by Cyril Zakka on 1/12/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI

@main
struct Diffusion_macOSApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()

        }
        .commands {
            // Add an Import Model menu item in the File menu, trigger the menu with keyboard shortcut COMMAND-SHIFT-I
            CommandGroup(replacing: CommandGroupPlacement.newItem) {
                Button(action: {
                    // Using a Published variable in singleton Settings to track the status of the import panel across different parts of the app.
                    Settings.shared.isShowingImportPanel = true
                }) {
                    Text("Import Model…")
                }
                .keyboardShortcut("I", modifiers: [.command, .shift])
            }
        }
    }
}
