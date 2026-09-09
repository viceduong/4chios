import XCTest
@testable import ChanCore

final class PostHTMLParserTests: XCTestCase {
    private func body(_ html: String) -> PostBody {
        PostHTMLParser.parse(html)
    }

    func testPlainTextAndEntities() {
        let parsed = body("AT&amp;T &gt; others &lt;3 &quot;quoted&quot; &#039;x&#039; &nbsp;end")
        XCTAssertEqual(parsed.plainText, "AT&T > others <3 \"quoted\" 'x' \u{00A0}end")
        XCTAssertEqual(parsed.runs.count, 1)
    }

    func testLineBreaks() {
        XCTAssertEqual(body("one<br>two<br/>three").plainText, "one\ntwo\nthree")
    }

    func testInlineFormatting() {
        let parsed = body("<b>bold</b> <i>italic</i> <u>under</u>")
        XCTAssertEqual(parsed.plainText, "bold italic under")
        XCTAssertEqual(parsed.runs[0].style, .bold)
        XCTAssertEqual(parsed.runs[1].text, " ")
        XCTAssertEqual(parsed.runs[2].style, .italic)
        XCTAssertEqual(parsed.runs[4].style, .underline)
    }

    func testGreentext() {
        let parsed = body("<span class=\"quote\">&gt;be me</span>")
        XCTAssertEqual(parsed.plainText, ">be me")
        XCTAssertEqual(parsed.runs[0].style, .quote)
    }

    func testSpoiler() {
        let parsed = body("visible <s>secret</s>")
        XCTAssertEqual(parsed.plainText, "visible secret")
        XCTAssertTrue(parsed.runs[1].style.contains(.spoiler))
    }

    func testQuoteLink() {
        let parsed = body("<a href=\"#p123456\" class=\"quotelink\">&gt;&gt;123456</a>")
        XCTAssertEqual(parsed.runs[0].link, .quote(PostNumber(123456)))
        XCTAssertEqual(parsed.quotedPosts, [PostNumber(123456)])
        XCTAssertEqual(parsed.runs[0].link?.url?.absoluteString, "ch4ios://post/123456")
    }

    func testDeadLink() {
        let parsed = body("<a href=\"#p42\" class=\"deadlink\">&gt;&gt;42</a>")
        XCTAssertEqual(parsed.runs[0].link, .dead(PostNumber(42)))
        XCTAssertTrue(parsed.runs[0].style.contains(.deadLink))
    }

    func testExternalLink() {
        let parsed = body("<a href=\"https://example.com/x\">site</a>")
        XCTAssertEqual(parsed.runs[0].link, .external(URL(string: "https://example.com/x")!))
    }

    func testCodeBlockIsMonospacedAndKeepsNewlines() {
        let parsed = body("<pre class=\"prettyprint\">func f() {\n  return\n}</pre>")
        XCTAssertEqual(parsed.plainText, "func f() {\n  return\n}")
        XCTAssertTrue(parsed.runs[0].style.contains(.code))
    }

    func testUnknownTagsUnwrapAndWbrIsDropped() {
        let parsed = body("<div><foo bar=\"1\">kept</foo><wbr>gone</div>")
        XCTAssertEqual(parsed.plainText, "keptgone")
    }

    func testNestedStylesCombine() {
        let parsed = body("<b><i>both</i></b>")
        XCTAssertEqual(parsed.runs[0].style, [.bold, .italic])
    }

    func testMismatchedCloseIsIgnored() {
        let parsed = body("<b>bold</i> still bold</b>")
        XCTAssertEqual(parsed.plainText, "bold still bold")
        XCTAssertEqual(parsed.runs.count, 1)
        XCTAssertEqual(parsed.runs[0].style, .bold)
    }

    func testEmptyAndWhitespaceBodies() {
        XCTAssertTrue(body("").isEmpty)
        XCTAssertTrue(body("<br><br>").isEmpty)
        XCTAssertTrue(body("   ").isEmpty)
    }

    func testRealWorldSample() {
        let html = """
        <span class="quote">&gt;implying</span><br><br>Here is a <a href="#p999" class="quotelink">&gt;&gt;999</a> \
        and an <a href="https://example.org" target="_blank">external link</a>.<br>A <s>spoiler</s> and \
        <b>bold</b>.
        """
        let parsed = body(html)
        XCTAssertEqual(parsed.quotedPosts, [PostNumber(999)])
        XCTAssertEqual(parsed.runs.filter { $0.style.contains(.quote) }.count, 1)
        XCTAssertEqual(parsed.runs.filter { $0.style.contains(.spoiler) }.count, 1)
        XCTAssertEqual(parsed.runs.filter { $0.style.contains(.bold) }.count, 1)
    }
}
