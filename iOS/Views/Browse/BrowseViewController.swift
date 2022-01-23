//
//  BrowseViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit

class BrowseViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Browse"
        
        navigationController?.navigationBar.prefersLargeTitles = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Temporary -- for testing purposes
        let vc = SourceBrowseViewController(source: SourceManager.shared.sources.first!)
        navigationController?.pushViewController(vc, animated: true)
    }
}
