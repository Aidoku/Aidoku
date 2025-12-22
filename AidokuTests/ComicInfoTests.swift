//
//  ComicInfoTests.swift
//  Aidoku
//
//  Created by Skitty on 12/5/25.
//

@testable import Aidoku
import AidokuRunner
import Foundation
import Testing

struct ComicInfoTests {
    @Test func testParsing() throws {
        let comicInfoXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ComicInfo>
          <Title>Title</Title>
          <Series>Series</Series>
          <Number>11</Number>
          <Volume>20</Volume>
          <AlternateSeries>Alternate Series</AlternateSeries>
          <SeriesGroup>Series Group</SeriesGroup>
          <Summary>Summary</Summary>
          <Year>2020</Year>
          <Month>10</Month>
          <Day>1</Day>
          <Writer>Writer</Writer>
          <Penciller>Penciller 1, Penciller 2</Penciller>
          <Inker>Inker</Inker>
          <Colorist>Colorist</Colorist>
          <Letterer>Letterer</Letterer>
          <CoverArtist>CoverArtist</CoverArtist>
          <Editor>Editor 1, Editor 2</Editor>
          <Publisher>Publisher</Publisher>
          <Genre>Genre</Genre>
          <Web>https://aidoku.app</Web>
          <PageCount>3</PageCount>
          <LanguageISO>en</LanguageISO>
          <AgeRating>9+ Only</AgeRating>
          <Characters>Character 1, Character 2</Characters>
          <Teams>Team 1, Team 2</Teams>
          <ScanInformation>ScanInformation</ScanInformation>
          <Pages>
            <Page Image="0" ImageSize="1833151" ImageWidth="1988" ImageHeight="3056" Type="FrontCover" />
            <Page Image="1" ImageSize="759685" />
            <Page Image="2" ImageSize="1512273" />
            <Page Image="3" ImageSize="1744159" />
          </Pages>
        </ComicInfo>
        """
        let parsed = try #require(ComicInfo.load(xmlString: comicInfoXML))
        #expect(parsed.title == "Title")
        #expect(parsed.series == "Series")
        #expect(parsed.number == "11")
        #expect(parsed.volume == 20)
        #expect(parsed.summary == "Summary")
        #expect(parsed.penciller == "Penciller 1, Penciller 2")
    }

    @Test func testSerialization() throws {
        let manga = AidokuRunner.Manga(
            sourceKey: "sourceKey",
            key: "mangaKey",
            title: "Series",
            cover: nil,
            artists: ["Artist 1", "Artist 2"],
            authors: ["Author 1", "Author 2"],
            description: "Summary",
            url: .init(string: "https://aidoku.app"),
            tags: ["Tag 1", "Tag 2"],
            status: .ongoing,
            contentRating: .safe,
            viewer: .rightToLeft
        )
        let chapter = AidokuRunner.Chapter(
            key: "chapterKey",
            title: "Title",
            chapterNumber: 5.5,
            volumeNumber: 10,
            dateUploaded: DateComponents(
                calendar: .current,
                year: 2025,
                month: 12,
                day: 5
            ).date,
            language: "en"
        )
        let comicInfo = ComicInfo.load(manga: manga, chapter: chapter)
        #expect(comicInfo.series == "Series")
        #expect(comicInfo.number == "5.5")
        #expect(comicInfo.volume == 10)
        #expect(comicInfo.title == "Title")
        #expect(comicInfo.penciller == "Artist 1, Artist 2")
        #expect(comicInfo.web == "https://aidoku.app")
        #expect(comicInfo.year == 2025)
        #expect(comicInfo.month == 12)
        #expect(comicInfo.day == 5)

        let reparsedManga = try #require(comicInfo.toManga())
        #expect(manga.sourceKey == reparsedManga.sourceKey)
        #expect(manga.key == reparsedManga.key)
        #expect(manga.title == reparsedManga.title)
        #expect(manga.authors == reparsedManga.authors)
        #expect(manga.artists == reparsedManga.artists)
        #expect(manga.description == reparsedManga.description)
        #expect(manga.url == reparsedManga.url)
        #expect(manga.viewer == reparsedManga.viewer)

        let reparsedChapter = try #require(comicInfo.toChapter())
        #expect(chapter.key == reparsedChapter.key)
        #expect(chapter.chapterNumber == reparsedChapter.chapterNumber)
        #expect(chapter.volumeNumber == reparsedChapter.volumeNumber)
        #expect(chapter.dateUploaded == reparsedChapter.dateUploaded)
    }
}
