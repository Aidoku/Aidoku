//
//  ListingsHeaderView.swift
//  Aidoku
//
//  Created by Skitty on 2/14/24.
//

import SwiftUI
import AidokuRunner

struct ListingsHeaderView: View {
    let source: AidokuRunner.Source
    @Binding var listings: [AidokuRunner.Listing]
    @Binding var selectedListing: Int

    @State private var error: Error?
    @State private var listingsLoaded: Bool = false

    var body: some View {
        Group {
            if let error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.headline)
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
                }
            } else if !listings.isEmpty || listingsLoaded {
                headerScrollView
                    .transition(.opacity)
            } else {
                Self.placeholder
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("refresh-listings"))) { _ in
            listingsLoaded = false
            self.error = nil
            Task {
                await load()
            }
        }
        .task {
            if listings.isEmpty {
                await load()
            }
        }
    }

    func load() async {
        do {
            let newListings = try await source.getListings()
            withAnimation {
                listings = newListings
                listingsLoaded = true
            }
        } catch {
            withAnimation {
                self.error = error
            }
        }
    }

    var headerScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let options = if source.features.providesHome {
                    [NSLocalizedString("HOME")] + listings.map { $0.name }
                } else {
                    listings.map { $0.name }
                }
                ForEach(options.indices, id: \.self) { offset in
                    let option = options[offset]
                    let active = selectedListing == offset
                    Button {
                        selectedListing = offset
                    } label: {
                        let label = Text(option)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(active ? Color.white : Color.primary)

                        if #available(iOS 26.0, *) {
                            label
                                .glassEffect(active ? .regular.tint(.accentColor) : .regular)
                        } else {
                            label
                                .background(
                                    RoundedRectangle(cornerRadius: 100)
                                        .fill(
                                            Color(
                                                uiColor: active
                                                    ? .tintColor
                                                    : .secondarySystemFill
                                            )
                                        )
                                )
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .scrollClipDisabledPlease()
        .padding(.top, -11)
    }

    static var placeholder: some View {
        // skeleton loading
        HStack(spacing: 6) {
            ForEach(0..<3) { _ in
                Text("Loading")
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .font(.footnote.weight(.medium))
                    .background(
                        RoundedRectangle(cornerRadius: 100)
                            .foregroundColor(.init(uiColor: .secondarySystemFill))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(
                                Color(uiColor: .tertiarySystemFill),
                                style: .init(lineWidth: 1)
                            )
                    }
                    .redacted(reason: .placeholder)
                    .shimmering()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, -11)
        .transition(.opacity)
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    @Previewable @State var selectedListing = 0
    @Previewable @State var listings: [AidokuRunner.Listing] = [
        .init(id: "1", name: "Listing 1"),
        .init(id: "2", name: "Listing 2")
    ]
    ListingsHeaderView(
        source: .demo(),
        listings: $listings,
        selectedListing: $selectedListing
    )
    .padding()
}
