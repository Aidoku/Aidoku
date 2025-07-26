//
//  TapZonesSelectView.swift
//  Aidoku
//
//  Created by Skitty on 7/24/25.
//

import SwiftUI

struct TapZonesSelectView: View {
    @State private var selectedTapZones: DefaultTapZones = .disabled

    static private let spacing: CGFloat = 12
    static private let minCardWidth: CGFloat = 160
    static private let leftColor = Color(uiColor: .systemBlue).opacity(0.3)
    static private let rightColor = Color(uiColor: .systemGreen).opacity(0.3)

    init() {
        self._selectedTapZones = State(
            initialValue: UserDefaults.standard.string(forKey: "Reader.tapZones")
                .flatMap(DefaultTapZones.init) ?? .disabled
        )
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: Self.minCardWidth), spacing: Self.spacing)
                ],
                spacing: Self.spacing
            ) {
                ForEach(DefaultTapZones.allCases, id: \.rawValue) { tapZone in
                    Button {
                        selectedTapZones = tapZone
                    } label: {
                        TapZoneCard(title: tapZone.title, selected: selectedTapZones == tapZone) {
                            if let regions = tapZone.tapZone {
                                layoutView(tapZone: regions)
                            } else {
                                switch tapZone {
                                    case .automatic:
                                        ZStack {
                                            layoutView(tapZone: .leftRight)
                                                .mask(DiagonalMask(reverse: false))
                                            layoutView(tapZone: .lShaped)
                                                .overlay(Color.black.opacity(0.05))
                                                .mask(DiagonalMask(reverse: true))
                                        }
                                    default:
                                        EmptyView()
                                }
                            }
                        }
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(NSLocalizedString("TAP_ZONES"))
        .onChange(of: selectedTapZones) { _ in
            UserDefaults.standard.setValue(selectedTapZones.value, forKey: "Reader.tapZones")
            NotificationCenter.default.post(name: .readerTapZones, object: nil)
        }
    }

    // swiftui view for tap zone regions
    @ViewBuilder
    func layoutView(tapZone: TapZone) -> some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(tapZone.regions.indices, id: \.self) { index in
                    let region = tapZone.regions[index]
                    let frame = CGRect(
                        x: region.bounds.origin.x * geometry.size.width,
                        y: region.bounds.origin.y * geometry.size.height,
                        width: region.bounds.size.width * geometry.size.width,
                        height: region.bounds.size.height * geometry.size.height
                    )

                    Rectangle()
                        .fill(region.type == .left ? Self.leftColor : Self.rightColor)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }
}

private struct TapZoneCard<Content: View>: View {
    let title: String
    let selected: Bool
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    static var outerCornerRadius: CGFloat { 10 }
    static var innerCornerRadius: CGFloat { 20 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                ZStack {
                    content
                        .mask(RoundedRectangle(cornerRadius: Self.innerCornerRadius - 12))
                        .padding(12)

                    RoundedRectangle(cornerRadius: Self.innerCornerRadius)
                        .strokeBorder(Color(uiColor: .secondarySystemFill))
                        .aspectRatio(9/16, contentMode: .fill)
                }
                .background(Color.white)
                .mask(RoundedRectangle(cornerRadius: Self.innerCornerRadius))
                .padding(.horizontal, 15)

                Text(title)
                    .fontWeight(selected ? .medium : .regular)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)

            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .imageScale(.large)
                .foregroundStyle(Color(uiColor: selected ? .tintColor : .secondarySystemFill))
                .padding(8)
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Self.outerCornerRadius)
                    .fill(
                        selected
                            ? .accentColor.opacity(colorScheme == .dark ? 0.1 : 0.05)
                            : Color(uiColor: .quaternarySystemFill)
                    )
                if selected {
                    RoundedRectangle(cornerRadius: Self.outerCornerRadius)
                        .fill(Color(uiColor: .quaternarySystemFill).opacity(0.3))
                }
                RoundedRectangle(cornerRadius: Self.outerCornerRadius)
                    .strokeBorder(selected ? .accentColor : Color(uiColor: .secondarySystemFill))
            }
        }
    }
}

private struct CardButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: TapZoneCard<EmptyView>.outerCornerRadius)
                        .fill(Color.black)
                        .opacity(colorScheme == .dark ? 0.5 : 0.3)
                }
            }
    }
}

private struct DiagonalMask: View {
    var reverse: Bool

    var body: some View {
        GeometryReader { geo in
            Path { path in
                if reverse {
                    // bottom right
                    path.move(to: CGPoint(x: geo.size.width, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                } else {
                    // top left
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                }
                path.closeSubpath()
            }
            .fill(Color.white)
        }
    }
}

#Preview {
    PlatformNavigationStack {
        TapZonesSelectView()
    }
}
