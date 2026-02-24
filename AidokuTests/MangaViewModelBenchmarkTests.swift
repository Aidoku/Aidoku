import Testing
import Foundation
import AidokuRunner
@testable import Aidoku

@Suite struct MangaViewModelBenchmarkTests {

    // Benchmark 1: Current Implementation (compactMap + max)
        @Test("Performance: Current Implementation")
        func testPerformanceCurrentImplementation() {
            // Setup data locally within the test to ensure isolation
            let data = setupData()
            let chapters = data.chapters
            let readingHistory = data.readingHistory
            let downloadStatus = data.downloadStatus

            // We will run it multiple times to get an average
        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0..<100 {
            let lastReadChapter = chapters.compactMap { chapter -> (AidokuRunner.Chapter, Int)? in
                guard let history = readingHistory[chapter.id], history.page != -1 else { return nil }

                // Ensure chapter is accessible
                let isDownloaded = downloadStatus[chapter.key] == .finished
                if chapter.locked && !isDownloaded { return nil }

                return (chapter, history.date)
            }.max(by: { $0.1 < $1.1 })?.0

            _ = lastReadChapter
        }

        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("Current Implementation Time (100 runs): \(timeElapsed) seconds")
    }

    // Benchmark 2: Optimized Implementation (For Loop)
        @Test("Performance: Optimized Loop")
        func testPerformanceOptimizedLoop() {
            let data = setupData()
            let chapters = data.chapters
            let readingHistory = data.readingHistory
            let downloadStatus = data.downloadStatus

            let startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            var bestChapter: AidokuRunner.Chapter?
            var bestDate = -1

            for chapter in chapters {
                if let history = readingHistory[chapter.id], history.page != -1 {
                    let isDownloaded = downloadStatus[chapter.key] == .finished
                    if !chapter.locked || isDownloaded {
                        if history.date > bestDate {
                            bestDate = history.date
                            bestChapter = chapter
                        }
                    }
                }
            }

            _ = bestChapter
        }

        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("Optimized Loop Time (100 runs): \(timeElapsed) seconds")
    }

        struct BenchmarkData {
            let chapters: [AidokuRunner.Chapter]
            let readingHistory: [String: (page: Int, date: Int)]
            let downloadStatus: [String: DownloadStatus]
        }

        // Helper to setup data
        func setupData() -> BenchmarkData {
            var chapters: [AidokuRunner.Chapter] = []
            var readingHistory: [String: (page: Int, date: Int)] = [:]
            var downloadStatus: [String: DownloadStatus] = [:]

            // Setup 10,000 chapters
            chapters = (0..<10000).map { i in
                AidokuRunner.Chapter(
                    key: "ch\(i)",
                    title: "Chapter \(i)",
                    chapterNumber: Float(i),
                    dateUploaded: Date(),
                    locked: i % 10 == 0 // Every 10th chapter is locked
                )
            }

            // Simulate history: 50% of chapters read, scattered dates
            for _ in 0..<5000 {
                // Randomly pick chapters to have history
                let chapterIndex = Int.random(in: 0..<10000)
                let date = Int.random(in: 100000...200000)
                // Page -1 means completed, random page means in progress
                let page = Int.random(in: -1...100)
                readingHistory["ch\(chapterIndex)"] = (page: page, date: date)
            }

            // Simulate downloads: 10% of locked chapters downloaded
            for i in stride(from: 0, to: 10000, by: 10) where Int.random(in: 0...10) == 0 {
                downloadStatus["ch\(i)"] = .finished
            }

            return BenchmarkData(chapters: chapters, readingHistory: readingHistory, downloadStatus: downloadStatus)
        }
    }
