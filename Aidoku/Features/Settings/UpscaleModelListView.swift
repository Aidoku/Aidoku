//
//  UpscaleModelListView.swift
//  Aidoku
//
//  Created by Skitty on 6/25/25.
//

import SwiftUI

struct UpscaleModelListView: View {
    @State private var models: [ModelInfo] = []
    @State private var availableModels: [ModelInfo] = []

    @State private var enabledModel: String?
    @State private var failedToLoad = false
    @State private var loading = true

    @State private var modelInfo: String?
    @State private var showModelInfoAlert = false

    var body: some View {
        List {
            Section(NSLocalizedString("ENABLED_MODEL")) {
                Button {
                    enabledModel = nil
                    ModelManager.shared.setEnabledModel(fileName: nil)
                } label: {
                    HStack {
                        Text(NSLocalizedString("NONE"))
                        Spacer()
                        if enabledModel == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)

                ForEach(models, id: \.file) { model in
                    Button {
                        enabledModel = model.file
                        ModelManager.shared.setEnabledModel(fileName: model.file)
                    } label: {
                        modelItem(model: model, installed: true)
                    }
                    .foregroundStyle(.primary)
                    .contextMenu {
                        Button(role: .destructive) {
                            if let index = models.firstIndex(where: { $0.file == model.file }) {
                                models.remove(at: index)
                            }
                            remove(modelFiles: [model.file])
                        } label: {
                            Label(NSLocalizedString("REMOVE"), systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: delete)
            }

            if loading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.secondary)
            } else {
                if !availableModels.isEmpty {
                    Section {
                        ForEach(availableModels, id: \.file) { model in
                            modelItem(model: model, installed: false)
                        }
                    } header: {
                        Text(NSLocalizedString("AVAILABLE_MODELS"))
                    }
                } else if failedToLoad {
                    Section {
                        VStack(spacing: 4) {
                            Text(NSLocalizedString("NO_AVAILABLE_MODELS"))
                                .fontWeight(.medium)
                            Text(NSLocalizedString("NO_AVAILABLE_MODELS_TEXT"))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("UPSCALING_MODELS"))
        .alert(NSLocalizedString("MODEL_INFO"), isPresented: $showModelInfoAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {
                modelInfo = nil
            }
        } message: {
            if let modelInfo {
                Text(modelInfo)
            }
        }
        .task {
            enabledModel = ModelManager.shared.getEnabledModelFileName()
            models = await ModelManager.shared.getInstalledModels()
            if let fetchedModels = await ModelManager.shared.getAvailableModels() {
                availableModels = fetchedModels
            } else {
                failedToLoad = true
            }
            withAnimation {
                loading = false
            }
        }
    }

    func modelItem(model: ModelInfo, installed: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.name ?? model.file)
                    .foregroundStyle(.primary)
                if let size = model.size {
                    HStack {
                        Image(systemName: "externaldrive.fill")
                            .imageScale(.small)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let info = model.info {
                Button {
                    modelInfo = info
                    showModelInfoAlert = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
            }
            if installed {
                if enabledModel == model.file {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            } else {
                GetButton {
                    do {
                        try await ModelManager.shared.downloadModel(model)
                        let installedModels = await ModelManager.shared.getInstalledModels()
                        withAnimation {
                            if let index = availableModels.firstIndex(where: { $0.file == model.file }) {
                                availableModels.remove(at: index)
                            }
                            models = installedModels
                        }
                        return true
                    } catch {
                        LogManager.logger.error("Error downloading model: \(error.localizedDescription)")
                        return false
                    }
                }
            }
        }
    }

    func delete(at offsets: IndexSet) {
        let files = offsets.map { models[$0].file }
        models.remove(atOffsets: offsets)
        remove(modelFiles: files)
    }

    func remove(modelFiles: [String]) {
        Task {
            for file in modelFiles {
                await ModelManager.shared.removeModel(withFile: file)
                if enabledModel == file {
                    enabledModel = nil
                }
            }
            if let newAvailableModels = await ModelManager.shared.getAvailableModels() {
                withAnimation {
                    availableModels = newAvailableModels
                }
            }
        }
    }
}
