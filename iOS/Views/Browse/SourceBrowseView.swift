//
//  SourceBrowseView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/14/22.
//

import SwiftUI

struct SourceBrowseView: UIViewControllerRepresentable {
    typealias UIViewControllerType = SourceBrowseViewController
    
    let source: Source
    
    func makeUIViewController(context: Context) -> UIViewControllerType {
        SourceBrowseViewController(source: source)
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
    }
}
