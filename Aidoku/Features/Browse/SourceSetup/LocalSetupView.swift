//
//  LocalSetupView.swift
//  Aidoku
//
//  Created by Skitty on 6/5/25.
//

import SwiftUI

struct LocalSetupView: View {
    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
        List {
            Section {
                SettingHeaderView(
                    icon: .raw(Image(.local)),
                    title: NSLocalizedString("LOCAL_FILES"),
                    subtitle: NSLocalizedString("LOCAL_FILES_INFO")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if #available(iOS 26.0, *) {
                    Button(role: .confirm) {
                        Task {
                            await submit()
                        }
                    }
                } else {
                    Button {
                        Task {
                            await submit()
                        }
                    } label: {
                        Text(NSLocalizedString("ADD")).bold()
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("LOCAL_FILES_SETUP"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    static func infoView(title: LocalizedStringKey, subtitle: LocalizedStringKey, error: Bool = false) -> some View {
        let titleColor = error
            ? Color(uiColor: UIColor(dynamicProvider: { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? .init(red: 0.8, green: 0.76, blue: 0.76, alpha: 1)
                    : .init(red: 0.4, green: 0.2, blue: 0.2, alpha: 1)
            }))
            : Color.primary
        let subtitleColor = error ? Color(red: 0.58, green: 0.44, blue: 0.44) : .secondary

        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .fontWeight(.medium)
                .foregroundStyle(titleColor)
            Text(subtitle)
                .foregroundStyle(subtitleColor)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .listRowBackground(error ? Color.red.opacity(0.1) : nil)
    }

    func submit() async {
        let config = CustomSourceConfig.local
        let source = config.toSource()

        // add to coredata
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let result = CoreDataManager.shared.createSource(source: source, context: context)
            result.customSource = config.encode() as NSObject
            try? context.save()
        }

        SourceManager.shared.sources.append(source)
        SourceManager.shared.sortSources()

        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)

        path.dismiss()
    }
}
