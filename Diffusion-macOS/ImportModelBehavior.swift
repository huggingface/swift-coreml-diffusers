//
//  ImportModelBehavior.swift
//  Diffusion-macOS
//
//  Created by Dolmere on 19/06/2023
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE


import SwiftUI

// A view modifier to add a .fileImporter import panel into a view
struct ImportModelBehavior: ViewModifier {

    @ObservedObject var modelsViewModel: ModelsViewModel
    @ObservedObject private var settings = Settings.shared

    @State var isBadSelectionAlertShown: Bool = false
    @State private var importPanelState: Bool = false {
        didSet {
            if settings.isShowingImportPanel != importPanelState {
                settings.isShowingImportPanel = importPanelState
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $importPanelState, allowedContentTypes: [.folder, .zip]) { result in
                do {
                    let url = try result.get()
                    if url.hasDirectoryPath {
                        let fileManager = FileManager.default
                        let contents = try fileManager.contentsOfDirectory(atPath: url.path)
                        
                        if contents.contains("merges.txt") && contents.contains("vocab.json") {
                            // Folder contains the required filenames
                            do {
                                try FileManager.default.moveItem(at: url, to: modelsViewModel.modelsFolderURL.appendingPathComponent(url.lastPathComponent))
                            } catch {
                                // Error handling
                                print("Error: \(error.localizedDescription)")
                            }
                        } else {
                            // Folder does not contain the required filenames
                            isBadSelectionAlertShown = true
                        }
                    } else if url.pathExtension == "zip" {
                        // Handle selected zip file
                        extractZipFile(from: url, to: modelsViewModel.modelsFolderURL)
                    } else {
                        // Invalid selection
                        isBadSelectionAlertShown = true
                    }
                    
                } catch {
                    // Error handling
                    print("Error: \(error.localizedDescription)")
                }
            }
            .alert(isPresented: $isBadSelectionAlertShown) {
                Alert(
                    title: Text("Not a model"),
                    message: Text("The selected folder does not appear to be a model. Please select an extracted model folder or a zip compressed model file."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onReceive(settings.$isShowingImportPanel) { newValue in
//                print("Settings.shared.isShowingImportPanel changed to \(newValue)")
                self.importPanelState = newValue
            }
    }
}
