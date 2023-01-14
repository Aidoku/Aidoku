//
//  fetch.swift
//  Aidoku
//
//  Created by Skitty on 1/13/23.
//

import JavaScriptCore

let fetch: @convention(block) (String, [String: Any]) -> Promise = { url, options in
    print("fetch", url, options)
    return Promise { resolve, reject in
        guard let url = URL(string: url) else {
            reject("Invalid URL (\(url))")
            return
        }

        let method = (options["method"] as? String) ?? "GET"
        let headers: [String: String] = (options["headers"] as? [String: String]) ?? [:]
        let body = options["body"] as? String

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        request.httpBody = body?.data(using: .utf8)
        request.setValue("Aidoku", forHTTPHeaderField: "x-requested-with")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                reject(error.localizedDescription)
            } else if let data = data {
                let status: Int
                if let res = response as? HTTPURLResponse {
//                    res.allHeaderFields
                    status = res.statusCode
                } else {
                    status = 200
                }
                resolve(Response(data: data, status: status))
            } else {
                reject("\(url) is empty")
            }
        }.resume()
    }
}

@objc protocol ResponseExports: JSExport {
    var status: Int { get }
    func text() -> Promise
}

class Response: NSObject, ResponseExports {

    var data: Data
    var status: Int

    init(data: Data, status: Int) {
        self.data = data
        self.status = status
    }

    func text() -> Promise {
        Promise { resolve, reject in
            if let string = String(data: self.data, encoding: .utf8) {
                resolve(string)
            } else {
                reject("Unable to decode")
            }
        }
    }
}
