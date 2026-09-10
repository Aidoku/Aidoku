import Foundation
import ZIPFoundation

enum ReaderTextContent {
    static func load(page: Page) -> String? {
        if let text = page.text { return text }
        guard let zipURL = page.zipURL.flatMap(URL.init(string:)), let filePath = page.imageURL else { return nil }
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            guard let entry = archive.entry(at: filePath) else { return nil }
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
