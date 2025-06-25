//
//  ModelManager.swift
//  Aidoku
//
//  Created by Skitty on 6/25/25.
//

import CoreML

struct ModelList: Decodable {
    let models: [ModelInfo]
}

struct ModelInfo: Codable {
    var name: String?
    var type: String?
    var info: String?
    var file: String
    var size: Int?
}

actor ModelManager {
    static let shared = ModelManager()

    static private let modelListUrl = URL(string: "http://localhost:8080/models.json")!
    static private let supportedModelTypes: Set<String> = ["waifu2x"]

    private var imageModelCache: [String: ImageModel] = [:]
    private var cachedModelList: ModelList?

    // download a model from the server and save to local disk
    func downloadModel(_ model: ModelInfo) async throws {
        let url = URL(string: model.file, relativeTo: Self.modelListUrl)!
        let (data, _) = try await URLSession.shared.data(from: url)
        // save model file
        let fileName = (model.file as NSString).lastPathComponent
        let fileURL = try modelsDirectory().appendingPathComponent(fileName)
        try data.write(to: fileURL)

        // save metadata
        let metadataURL = try metadataURL(forModelFile: fileName)
        let metadataData = try JSONEncoder().encode(model)
        try metadataData.write(to: metadataURL)
    }

    // remove a downloaded model from disk
    func removeModel(withFile modelFile: String) {
        let fileName = (modelFile as NSString).lastPathComponent
        guard let fileURL = try? modelsDirectory().appendingPathComponent(fileName) else { return }

        // remove model file
        try? FileManager.default.removeItem(at: fileURL)
        // remove metadata file
        if let metadataURL = try? metadataURL(forModelFile: fileName) {
            try? FileManager.default.removeItem(at: metadataURL)
        }
        // remove from cache
        imageModelCache[fileName] = nil
    }

    // get installed models from disk
    // fetches extra info from the server if available
    func getInstalledModels() async -> [ModelInfo] {
        guard
            let modelsDir = try? modelsDirectory(),
            let files = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path)
        else {
            return []
        }

        return files.compactMap { file in
            guard !file.hasSuffix(".json") else { return nil } // skip metadata files

            let filePath = (modelsDir.path as NSString).appendingPathComponent(file)

            // load model metadata
            let metadataPath = filePath + ".json"
            var info: ModelInfo?
            if let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)),
               let meta = try? JSONDecoder().decode(ModelInfo.self, from: data)
            {
                info = meta
                info?.file = file // ensure file field is just the local file name
            }
            if info == nil {
                info = ModelInfo(name: nil, type: nil, info: nil, file: file, size: nil)
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
               let fileSize = attrs[.size] as? NSNumber
            {
                info?.size = fileSize.intValue
            } else {
                info?.size = nil
            }
            return info
        }
    }

    // get available models from the server, filtering out those already installed
    func getAvailableModels() async -> [ModelInfo]? {
        guard
            let modelsDir = try? modelsDirectory(),
            let files = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path),
            let modelList = try? await fetchModelList()
        else {
            return nil
        }

        let installedFiles = Set(files)

        return modelList.models.filter {
            if let type = $0.type {
                Self.supportedModelTypes.contains(type)
                    && !installedFiles.contains((($0.file as NSString).lastPathComponent))
            } else {
                false
            }
        }
    }

    // set the currently enabled model
    func setEnabledModel(fileName: String?) {
        UserDefaults.standard.set(fileName, forKey: "enabledModelFile")
    }

    // get currently enabled model file name
    func getEnabledModelFileName() -> String? {
        UserDefaults.standard.string(forKey: "enabledModelFile")
    }

    // get an instance of the currently enabled model
    func getEnabledModel() throws -> ImageModel? {
        guard let fileName = getEnabledModelFileName() else {
            return nil
        }
        return try loadModel(info: .init(file: fileName))
    }
}

// MARK: - Helpers
extension ModelManager {
    // get the directory where models are stored
    private func modelsDirectory() throws -> URL {
        let modelsDir = FileManager.default.documentDirectory.appendingPathComponent("Models")
        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try FileManager.default.createDirectory(
                at: modelsDir,
                withIntermediateDirectories: true
            )
        }
        return modelsDir
    }

    // get the list of models from the server
    private func fetchModelList() async throws -> ModelList {
        if let cachedModelList {
            return cachedModelList
        }
        let modelList: ModelList = try await URLSession.shared.object(from: Self.modelListUrl)
        cachedModelList = modelList
        return modelList
    }

    // get the url to an installed model's metadata file
    private func metadataURL(forModelFile fileName: String) throws -> URL {
        try modelsDirectory().appendingPathComponent(fileName + ".json")
    }

    // load a usable instance of an image model from the disk
    private func loadModel(info: ModelInfo) throws -> ImageModel? {
        let modelsDir = try modelsDirectory()
        let fileName = (info.file as NSString).lastPathComponent
        let fileURL = modelsDir.appendingPathComponent(fileName)

        // return cached model if available
        if let cached = imageModelCache[fileName] {
            return cached
        }

        // get model type from given info, or try loading from metadata
        var modelType = info.type
        if modelType == nil {
            let metadataURL = try metadataURL(forModelFile: fileName)
            if let data = try? Data(contentsOf: metadataURL),
                let meta = try? JSONDecoder().decode(ModelInfo.self, from: data)
            {
                modelType = meta.type
            }
        }

        guard let modelType else { return nil }

        // load coreml model
        let compiledUrl = try MLModel.compileModel(at: fileURL)
        let mlModel = try MLModel(contentsOf: compiledUrl)
        let imageModel: ImageModel?

        switch modelType.lowercased() {
            case "waifu2x":
                if #available(iOS 16.0, *) {
                    imageModel = Waifu2x(model: mlModel)
                } else {
                    imageModel = nil
                }
            default:
                imageModel = nil
        }

        if let imageModel = imageModel {
            imageModelCache[fileName] = imageModel
        }
        return imageModel
    }
}
