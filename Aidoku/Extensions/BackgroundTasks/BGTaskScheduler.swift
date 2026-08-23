//
//  BGTaskScheduler.swift
//  Aidoku
//
//  Created by skitty on 8/16/26.
//

import BackgroundTasks

extension BGTaskScheduler {
    func submit(request: BGTaskRequest) async throws {
//        if #available(iOS 27.0, *) {
//            try await submitTaskRequest(request)
//        } else {
            try submit(request)
//        }
    }
}
