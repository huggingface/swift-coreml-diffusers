//
//  HelpContent.swift
//  Diffusion-macOS
//
//  Created by Pedro Cuenca on 7/2/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI

func helpContent(title: String, description: Text, showing: Binding<Bool>, width: Double = 400) -> some View {
    VStack {
        Text(title)
            .font(.title3)
            .padding(.top, 10)
            .padding(.all, 5)
        description
        .lineLimit(nil)
        .padding(.bottom, 5)
        .padding([.leading, .trailing], 15)
        Button {
            showing.wrappedValue.toggle()
        } label: {
            Text("Dismiss").frame(maxWidth: 200)
        }
        .padding(.bottom)
    }
    .frame(minWidth: width, idealWidth: width, maxWidth: width)
}

func helpContent(title: String, description: String, showing: Binding<Bool>, width: Double = 400) -> some View {
    helpContent(title: title, description: Text(description), showing: showing)
}

func helpContent(title: String, description: AttributedString, showing: Binding<Bool>, width: Double = 400) -> some View {
    helpContent(title: title, description: Text(description), showing: showing)
}


func modelsHelp(_ showing: Binding<Bool>) -> some View {
    let description = try! AttributedString(markdown:
        """
        Diffusers launches with a set of 5 models that can be downloaded from the Hugging Face Hub:
        
        **Stable Diffusion 1.4**
          
        This is the original Stable Diffusion model that changed the landscape of AI image generation.
        
        **Stable Diffusion 1.5**
        
        Same architecture as 1.4, but trained on additional images with a focus on aesthetics.
        
        **Stable Diffusion 2**
        
        Improved model, heavily retrained on millions of additional images.
        
        **Stable Diffusion 2.1**
        
        The last reference in the Stable Diffusion family. Works great with _negative prompts_.
        
        OFA small v0
        
        This is a special so-called _distilled_ model, half the size of the others. It runs faster and requires less RAM, try it out if you find generation slow!
        
        """, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    return helpContent(title: "Available Models", description: description, showing: showing, width: 600)
}

func promptsHelp(_ showing: Binding<Bool>) -> some View {
    let description = try! AttributedString(markdown:
        """
        **Prompt** is the description of what you want, and **negative prompt** is what you _don't want_.
        
        Use the negative prompt to tweak a previous generation (by removing unwanted items), or to provide hints for the model.
        
        Many people like to use negative prompts such as "ugly, bad quality" to make the model try harder. \
        Or consider excluding terms like "3d" or "realistic" if you're after particular drawing styles.
        
        """, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    return helpContent(title: "Prompt and Negative Prompt", description: description, showing: showing, width: 600)
}

func guidanceHelp(_ showing: Binding<Bool>) -> some View {
    let description =
        """
        Indicates how much the image should resemble the prompt.
        
        Low values produce more varied results, while excessively high ones \
        may result in image artifacts such as posterization.
        
        Values between 7 and 10 are usually good choices, but they affect \
        differently to different models.
        
        Feel free to experiment!
        """
    return helpContent(title: "Guidance Scale", description: description, showing: showing)
}

func stepsHelp(_ showing: Binding<Bool>) -> some View {
    let description =
         """
         How many times to go through the diffusion process.

         Quality increases the more steps you choose, but marginal improvements \
         get increasingly smaller.

         🧨 Diffusers currently uses the super efficient DPM Solver scheduler, \
         which produces great results in just 20 or 25 steps 🤯
         """
    return helpContent(title: "Inference Steps", description: description, showing: showing)
}

func seedHelp(_ showing: Binding<Bool>) -> some View {
    let description =
         """
         This is a number that allows you to reproduce a previous generation.
         
         Use it like this: select a seed and write a prompt, then generate an image. \
         Next, maybe add a negative prompt or tweak the prompt slightly, and see how the result changes. \
         Rinse and repeat until you are satisfied, or select a new seed to start over.

         If you select -1, a random seed will be chosen for you.
         """
    return helpContent(title: "Generation Seed", description: description, showing: showing)
}
