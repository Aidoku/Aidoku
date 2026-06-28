//
//  CoverRecoveryTests.swift
//  Aidoku
//
//  Created by neldra on 5/24/26.
//

@testable import Aidoku
import Foundation
import Nuke
import Testing

struct CoverRecoveryTests {
    @Test func recovers404() {
        #expect(CoverRecovery.shouldRecover(from: pipelineError(statusCode: 404)))
    }

    @Test func recovers410() {
        #expect(CoverRecovery.shouldRecover(from: pipelineError(statusCode: 410)))
    }

    @Test func recovers403() {
        #expect(CoverRecovery.shouldRecover(from: pipelineError(statusCode: 403)))
    }

    @Test func ignores5xx() {
        #expect(!CoverRecovery.shouldRecover(from: pipelineError(statusCode: 500)))
    }

    @Test func ignores401And451() {
        #expect(!CoverRecovery.shouldRecover(from: pipelineError(statusCode: 401)))
        #expect(!CoverRecovery.shouldRecover(from: pipelineError(statusCode: 451)))
    }

    @Test func ignoresNonPipelineErrors() {
        #expect(!CoverRecovery.shouldRecover(from: URLError(.notConnectedToInternet)))
    }

    private func pipelineError(statusCode: Int) -> ImagePipeline.Error {
        .dataLoadingFailed(error: DataLoader.Error.statusCodeUnacceptable(statusCode))
    }
}
