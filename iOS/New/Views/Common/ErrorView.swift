//
//  ErrorView.swift
//  Aidoku
//
//  Created by Skitty on 10/13/23.
//

import AidokuRunner
import SwiftUI

// source error warning triangle with associated text and retry button if applicable
struct ErrorView: View {
    let error: Error
    var retry: (() async -> Void)?

    @State private var loading = false

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                let text = if let error = error as? SourceError {
                    switch error {
                        case .missingResult:
                            NSLocalizedString("NO_RESULT")
                        case .unimplemented:
                            NSLocalizedString("UNIMPLEMENTED")
                        case .networkError:
                            NSLocalizedString("NETWORK_ERROR")
                        case .message(let string):
                            NSLocalizedString(string)
                    }
                } else if error is DecodingError {
                    NSLocalizedString("DECODING_ERROR")
                } else {
                    NSLocalizedString("UNKNOWN_ERROR")
                }
                Text(text)
            }
            .foregroundStyle(.secondary)

            if let error = error as? SourceError {
                if case .unimplemented = error {
                    // don't show retry button
                } else if let retry {
                    HStack {
                        if loading {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Button {
                                withAnimation {
                                    loading = true
                                }
                                Task {
                                    await retry()
                                    withAnimation {
                                        loading = false
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.body.weight(.medium))
                                    Text(NSLocalizedString("RETRY"))
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
