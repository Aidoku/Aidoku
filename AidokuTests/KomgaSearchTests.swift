import Foundation
import Testing
@testable import Aidoku

@Suite struct KomgaSearchTests {
    @Test("Lucene metacharacters in full-text searches are escaped before JSON encoding")
    func escapesLuceneMetacharacters() throws {
        let query = "É [Group (Artist)]? A+B && C||D"
        let escaped = KomgaSearchBody.escapeLuceneQuery(query)
        let expected = "É \\[Group \\(Artist\\)\\]\\? A\\+B \\&\\& C\\|\\|D"

        #expect(escaped == expected)
        for character in "+-&|!(){}[]^\"~*?:\\/" {
            #expect(KomgaSearchBody.escapeLuceneQuery(String(character)) == "\\" + String(character))
        }

        let body = KomgaSearchBody(condition: nil, fullTextSearch: escaped)
        let data = try JSONEncoder().encode(body)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["fullTextSearch"] as? String == expected)
    }

    @Test("Lucene escaping leaves ordinary text unchanged")
    func preservesOrdinaryText() {
        #expect(KomgaSearchBody.escapeLuceneQuery("Title with spaces and 日本語") == "Title with spaces and 日本語")
    }
}
