//
//  ContentView.swift
//  GifUp
//
//  Created by Nathan Lawrence on 3/19/20.
//  Copyright © 2020 Team Nighthawk, LLC. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    let sampleGifPath = Bundle.main.url(forResource: "CExample", withExtension: "mp4")!
    
    @State var randomColorChange = Color.gray
    
    
    var body: some View {
        VStack {
            Spacer()
            VStack {
                
                Button(action: {
                    print("Beginning attempt.")
                    do {
                        try NaiveGifConverterService.buildGifFromAsset(at: self.sampleGifPath, forcingFramesPerSecond: 18) { (_) in
                            print("done naively")
                            self.randomColorChange = Color(hue: Double.random(in: 0...1), saturation: 0.5, brightness: 0.5)
                        }
                    }
                    catch let err {
                        print(err)
                    }

                }){
                    Text("Naive Approach (Sequential R/W)")
                }
                
                Button(action: {
                    print("Beginning attempt.")
                    do {
                        let service = AssetBulkGifConverterService()
                        
                        try service.buildGifFromAsset(at: self.sampleGifPath, forcingFramesPerSecond: 18) { (_) in
                            print("done threaded")
                            self.randomColorChange = Color(hue: Double.random(in: 0...1), saturation: 0.5, brightness: 0.5)
                        }
                    }
                    catch let err {
                        print(err)
                    }

                }){
                    Text("Asynchronous Frame Accumulation")
                }
                
                
            }.padding()
            Spacer()
        }
        .frame(minWidth: 0,
                maxWidth: .infinity, minHeight: 0,
                maxHeight: .infinity, alignment: .topLeading)
            .background(randomColorChange)
            .edgesIgnoringSafeArea(.all)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
