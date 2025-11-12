//
//  ListDivider.swift
//  Aidoku
//
//  Created by Skitty on 11/12/25.
//

import SwiftUI

struct ListDivider: View {
    var body: some View {
        // ios 26 changed the color and size of list separators but didn't change Divider's appearance
        if #available(iOS 26.0, *) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1)
        } else {
            Divider()
        }
    }
}
