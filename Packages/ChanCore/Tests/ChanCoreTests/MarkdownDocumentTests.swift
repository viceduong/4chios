import ChanCore
import XCTest

final class MarkdownDocumentTests: XCTestCase {
    // MARK: - Blocks

    func testWrappedLinesBecomeOneParagraph() {
        let blocks = MarkdownDocument.parse("The board is arguing\nabout GPUs again.")

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].spans.map(\.text).joined(), "The board is arguing about GPUs again.")
    }

    func testBlankLinesSeparateParagraphs() {
        let blocks = MarkdownDocument.parse("First.\n\nSecond.")

        XCTAssertEqual(blocks.count, 2)
        guard case .paragraph = blocks[0], case .paragraph = blocks[1] else {
            return XCTFail("expected two paragraphs, got \(blocks)")
        }
    }

    func testHeadingsCarryTheirLevel() {
        let blocks = MarkdownDocument.parse("# One\n## Two\n###### Six")

        XCTAssertEqual(blocks.count, 3)
        guard case .heading(1, _) = blocks[0],
              case .heading(2, _) = blocks[1],
              case .heading(6, _) = blocks[2] else {
            return XCTFail("expected heading levels, got \(blocks)")
        }
    }

    func testAHashWithoutASpaceIsNotAHeading() {
        let blocks = MarkdownDocument.parse("#2 is the best thread")

        guard case .paragraph = blocks[0] else { return XCTFail("expected a paragraph") }
        XCTAssertEqual(blocks[0].spans.map(\.text).joined(), "#2 is the best thread")
    }

    func testBulletsAndTheirNesting() {
        let blocks = MarkdownDocument.parse("- top\n  - nested\n    - deeper")

        XCTAssertEqual(blocks.count, 3)
        guard case .bullet(0, _) = blocks[0],
              case .bullet(1, _) = blocks[1],
              case .bullet(2, _) = blocks[2] else {
            return XCTFail("expected nested bullets, got \(blocks)")
        }
    }

    func testNestingIsCappedSoADeepListStaysOnScreen() {
        let blocks = MarkdownDocument.parse("- a\n" + String(repeating: " ", count: 40) + "- absurdly deep")

        guard case .bullet(3, _) = blocks[1] else { return XCTFail("expected the depth to be capped") }
    }

    func testNumberedItemsKeepTheNumberTheModelWrote() {
        let blocks = MarkdownDocument.parse("1. first\n2. second\n10) tenth")

        guard case .numbered(_, "1.", _) = blocks[0],
              case .numbered(_, "2.", _) = blocks[1],
              case .numbered(_, "10.", _) = blocks[2] else {
            return XCTFail("expected numbered markers, got \(blocks)")
        }
    }

    func testARuleIsNotMistakenForABullet() {
        XCTAssertEqual(MarkdownDocument.parse("---"), [.rule])
        XCTAssertEqual(MarkdownDocument.parse("- - -"), [.rule])
        guard case .bullet = MarkdownDocument.parse("- -text")[0] else {
            return XCTFail("a bullet with a leading dash in its text is still a bullet")
        }
    }

    func testConsecutiveQuoteLinesMerge() {
        let blocks = MarkdownDocument.parse("> quoted one\n> quoted two")

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].spans.map(\.text).joined(), "quoted one quoted two")
    }

    func testFencedCodeKeepsItsContentAndLineBreaks() {
        let blocks = MarkdownDocument.parse("```\nlet x = 1\n**not bold**\n```")

        XCTAssertEqual(blocks.count, 1)
        guard case .code(let code) = blocks[0] else { return XCTFail("expected code, got \(blocks)") }
        XCTAssertEqual(code, "let x = 1\n**not bold**")
        XCTAssertTrue(code.contains("**"), "emphasis markers inside a fence stay literal")
    }

    func testAnUnterminatedFenceStillRendersAsCode() {
        let blocks = MarkdownDocument.parse("```\nlet x = 1")

        guard case .code = blocks[0] else { return XCTFail("expected code, got \(blocks)") }
    }

    func testATableDegradesToParagraphsRatherThanBreaking() {
        let blocks = MarkdownDocument.parse("| a | b |\n| - | - |\n| 1 | 2 |")

        guard case .paragraph = blocks[0] else { return XCTFail("expected a paragraph") }
        XCTAssertEqual(blocks.count, 1)
    }

    // MARK: - Inline

    private func runs(_ text: String) -> [MarkdownSpan] {
        MarkdownDocument.inline(text)
    }

    func testBoldItalicAndStrikethrough() {
        XCTAssertEqual(runs("**bold**"), [MarkdownSpan(text: "bold", bold: true)])
        XCTAssertEqual(runs("*italic*"), [MarkdownSpan(text: "italic", italic: true)])
        XCTAssertEqual(runs("~~gone~~"), [MarkdownSpan(text: "gone", strikethrough: true)])
        XCTAssertEqual(runs("__bold__"), [MarkdownSpan(text: "bold", bold: true)])
        XCTAssertEqual(runs("_italic_"), [MarkdownSpan(text: "italic", italic: true)])
    }

    func testNestedEmphasisCombines() {
        XCTAssertEqual(
            runs("***both***"),
            [MarkdownSpan(text: "both", bold: true, italic: true)]
        )
    }

    func testTextAroundEmphasisIsPreserved() {
        let spans = runs("this is **very** good")

        XCTAssertEqual(spans.map(\.text), ["this is ", "very", " good"])
        XCTAssertEqual(spans[1].bold, true)
        XCTAssertEqual(spans[0].isPlain, true)
        XCTAssertEqual(spans[2].isPlain, true)
    }

    func testCodeSpansAreLiteral() {
        XCTAssertEqual(
            runs("use `a * b` here").map(\.kind),
            [.text, .code, .text]
        )
        XCTAssertEqual(runs("`a * b`").first?.text, "a * b", "emphasis inside code is not parsed")
    }

    func testLinksCarryTheirDestination() {
        let spans = runs("see [the docs](https://example.com/x)")

        XCTAssertEqual(spans[1].text, "the docs")
        XCTAssertEqual(spans[1].kind, .link(URL(string: "https://example.com/x")))
    }

    func testAMalformedLinkStaysAsWritten() {
        XCTAssertEqual(runs("[no destination]").map(\.text), ["[no destination]"])
    }

    func testUnmatchedMarkersAreLeftAlone() {
        // The property that matters most: a stray asterisk must not swallow the
        // rest of the answer.
        XCTAssertEqual(runs("2 * 3 = 6").map(\.text), ["2 * 3 = 6"])
        XCTAssertTrue(runs("2 * 3 = 6").allSatisfy(\.isPlain))
    }

    func testUnderscoresInsideIdentifiersAreNotEmphasis() {
        XCTAssertEqual(runs("saved_media and post_bookmark").map(\.text), ["saved_media and post_bookmark"])
        XCTAssertTrue(runs("saved_media").allSatisfy(\.isPlain))
    }

    func testBackslashEscapesAMarker() {
        XCTAssertEqual(runs("\\*not italic\\*").map(\.text), ["*not italic*"])
        XCTAssertTrue(runs("\\*not italic\\*").allSatisfy(\.isPlain))
    }

    func testRealisticModelOutputParsesEndToEnd() {
        let text = """
        ## What is happening

        The board is arguing about **GPU pricing** again.

        - a claim about a *leak*
        - a counter-claim

        1. first
        2. second

        > a quoted line

        ```
        no *emphasis* here
        ```

        ---
        """

        let blocks = MarkdownDocument.parse(text)

        XCTAssertEqual(blocks.count, 9, "got \(blocks)")
        guard case .heading(2, _) = blocks[0],
              case .paragraph = blocks[1],
              case .bullet = blocks[2],
              case .bullet = blocks[3],
              case .numbered = blocks[4],
              case .numbered = blocks[5],
              case .quote = blocks[6],
              case .code = blocks[7] else {
            return XCTFail("unexpected block sequence: \(blocks)")
        }
        XCTAssertEqual(blocks[8], .rule)
    }
}
