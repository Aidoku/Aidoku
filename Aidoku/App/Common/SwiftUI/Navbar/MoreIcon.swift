//
//  MoreIcon.swift
//  Aidoku
//
//  Created by Skitty on 9/23/25.
//

import SwiftUI

struct MoreIcon: View {
    var body: some View {
        Image(systemName: {
            if #available(iOS 26.0, *) {
                "ellipsis"
            } else {
                "ellipsis.circle"
            }
        }())
    }
}
