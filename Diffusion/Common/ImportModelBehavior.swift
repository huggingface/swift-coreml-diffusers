//
//  ImportModelBehavior.swift
//  Diffusion-macOS
//
//  Created by Dolmere on 19/06/2023
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE


import SwiftUI
import ZIPFoundation

// A view modifier to add a .fileImporter import panel into a view
struct ImportModelBehavior: ViewModifier {

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
                        
                        if contents.contains(where: { $0.caseInsensitiveCompare("merges.txt") == .orderedSame }) && contents.contains(where: { $0.caseInsensitiveCompare("vocab.json") == .orderedSame }) {
                            // Folder contains the required filenames
                            do {
                                try fileManager.moveItem(at: url, to: Settings.shared.applicationSupportURL().appendingPathComponent("hf-diffusion-models").appendingPathComponent(url.lastPathComponent))
                            } catch {
                                // Error handling
                                print("Error: \(error.localizedDescription)")
                            }
                        } else {
                            // Folder does not contain the required filenames
                            isBadSelectionAlertShown = true
                        }
                    } else if url.pathExtension == "zip" {
                        DispatchQueue.global(qos: .background).async {
                            do {
                                let extractedURL = Settings.shared.applicationSupportURL().appendingPathComponent("hf-diffusion-models").appendingPathComponent(url.deletingPathExtension().lastPathComponent)
                                try FileManager.default.createDirectory(at: extractedURL, withIntermediateDirectories: true, attributes: nil)

                                if let archive = Archive(url: url, accessMode: .read) {
                                    for entry in archive {
                                        // Skip hidden and __MACOSX files
                                        let filename = entry.path.components(separatedBy: "/").last ?? ""
                                        if !filename.hasPrefix(".") && filename.lowercased() != "__macosx" {
                                            let destinationURL = extractedURL.appendingPathComponent(entry.path)
                                            let _ = try archive.extract(entry, to: destinationURL)
                                        }
                                    }
                                }

                                let extractedContents = try FileManager.default.contentsOfDirectory(atPath: extractedURL.path)
                                if extractedContents.contains(where: { $0.caseInsensitiveCompare("merges.txt") == .orderedSame }) && extractedContents.contains(where: { $0.caseInsensitiveCompare("vocab.json") == .orderedSame }) {
                                    // Files successfully extracted
                                } else {
                                    // Delete the extraction and post an alert that it's not properly formatted
                                    try? FileManager.default.removeItem(at: extractedURL)
                                    isBadSelectionAlertShown = true
                                }
                            } catch {
                                print("Error unzipping selected zip file: \(error)")
                            }
                        }
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
                    title: Text("Invalid model"),
                    message: Text("The selected folder does not appear to contain a Core ML Stable Diffusion model. Please, select an extracted model folder or a zip compressed model file."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onReceive(settings.$isShowingImportPanel) { newValue in
                self.importPanelState = newValue
            }
    }
}
