//
//  ErrorView.swift
//  Aidoku
//
//  Created by Skitty on 10/13/23.
//

import AidokuRunner
import SwiftUI
import Wasm3

// source error warning triangle with associated text and retry button if applicable
struct ErrorView: View {
    let error: Error
    var restart: (() async throws -> Void)?
    var retry: (() async -> Void)?

    @State private var loading = false

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                let text = error.aidokuDescription()
                Text(text)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)

            if let retry {
                if let error = error as? SourceError {
                    if case .unimplemented = error {
                        // don't show retry button
                    } else {
                        retryButton(action: retry)
                    }
                } else if let restart, let error = error as? Wasm3Error {
                    switch error {
                        case .trap, .runtimeDisabled:
                            retryButton(title: NSLocalizedString("RESTART")) {
                                do {
                                    try await restart()
                                    await retry()
                                } catch {
                                    LogManager.logger.error("Failed to restart source: \(error)")
                                }
                            }
                        default:
                            EmptyView()
                    }
                }
            }
        }
    }

    @ViewBuilder
    func retryButton(title: String = NSLocalizedString("RETRY"), action: @escaping () async -> Void) -> some View {
        HStack {
            if loading {
                ProgressView().progressViewStyle(.circular)
            } else {
                Button {
                    withAnimation {
                        loading = true
                    }
                    Task {
                        await action()
                        withAnimation {
                            loading = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.medium))
                        Text(title)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.top, 4)
    }
}
