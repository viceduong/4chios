import Foundation

/// Converts 4chan's post HTML fragments into a platform-agnostic `PostBody`.
///
/// 4chan post bodies are a small, well-defined subset of HTML. This parser handles
/// exactly that subset — no third-party dependency, no WebView — and is fully
/// unit-tested so the rendering layers can trust its output.
public enum PostHTMLParser {
    public static func parse(_ html: String) -> PostBody {
        var parser = Parser()
        return parser.parse(html)
    }

    struct Parser {
        private var runs: [PostRun] = []
        private var buffer = ""
        private var style: PostStyle = []
        private var link: PostLink?
        private var stack: [(name: String, style: PostStyle, link: PostLink?)] = []

        mutating func parse(_ html: String) -> PostBody {
            let characters = Array(html)
            var index = 0

            while index < characters.count {
                if characters[index] == "<" {
                    guard let end = characters[(index + 1)...].firstIndex(of: ">") else {
                        buffer.append(contentsOf: characters[index...])
                        break
                    }
                    handle(String(characters[(index + 1)..<end]))
                    index = end + 1
                } else {
                    buffer.append(characters[index])
                    index += 1
                }
            }

            flush()
            return PostBody(runs: runs)
        }

        private mutating func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(PostRun(text: Self.decodeEntities(buffer), style: style, link: link))
            buffer.removeAll(keepingCapacity: true)
        }

        private mutating func handle(_ rawTag: String) {
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { return }

            if tag.hasPrefix("/") {
                let name = String(tag.dropFirst())
                    .split(whereSeparator: { $0 == " " || $0 == "/" })
                    .first
                    .map { String($0).lowercased() } ?? ""
                guard !name.isEmpty,
                      let position = stack.lastIndex(where: { $0.name == name }) else { return }
                flush()
                let entry = stack[position]
                style = entry.style
                link = entry.link
                stack.removeSubrange(position...)
                return
            }

            let name = Self.tagName(of: tag)
            let attributes = Self.tagAttributes(of: tag)

            switch name {
            case "br":
                flush()
                buffer.append("\n")
            case "wbr", "img", "embed", "iframe", "video", "audio", "source", "meta", "link", "input", "hr":
                break
            default:
                flush()
                stack.append((name, style, link))
                apply(name: name, attributes: attributes)
            }
        }

        private mutating func apply(name: String, attributes: [String: String]) {
            switch name {
            case "b", "strong":
                style.insert(.bold)
            case "i", "em":
                style.insert(.italic)
            case "u":
                style.insert(.underline)
            case "s", "strike", "del":
                style.insert(.spoiler)
            case "pre", "code", "tt":
                style.insert(.code)
            case "span":
                let classes = attributes["class"] ?? ""
                if classes.contains("quote") { style.insert(.quote) }
                if classes.contains("sjis") { style.insert(.sjis) }
            case "a":
                let classes = attributes["class"] ?? ""
                let href = attributes["href"] ?? ""
                if classes.contains("quotelink") {
                    if let number = Self.postNumber(from: href) { link = .quote(number) }
                } else if classes.contains("deadlink") {
                    if let number = Self.postNumber(from: href) {
                        style.insert(.deadLink)
                        link = .dead(number)
                    }
                } else if let url = URL(string: href), let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https" {
                    link = .external(url)
                }
            default:
                break
            }
        }
    }
}

// MARK: - Token helpers

extension PostHTMLParser.Parser {
    static func tagName(of tag: String) -> String {
        let name = tag.prefix(while: { !$0.isWhitespace && $0 != "/" })
        return name.lowercased()
    }

    static func tagAttributes(of tag: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var index = tag.startIndex

        while index < tag.endIndex, !tag[index].isWhitespace { index = tag.index(after: index) }

        while index < tag.endIndex {
            while index < tag.endIndex, tag[index].isWhitespace { index = tag.index(after: index) }
            guard index < tag.endIndex else { break }

            var name = ""
            while index < tag.endIndex, tag[index] != "=", !tag[index].isWhitespace {
                name.append(tag[index])
                index = tag.index(after: index)
            }
            guard !name.isEmpty else { break }

            if index < tag.endIndex, tag[index] == "=" {
                index = tag.index(after: index)
                if index < tag.endIndex, tag[index] == "\"" || tag[index] == "'" {
                    let quote = tag[index]
                    index = tag.index(after: index)
                    var value = ""
                    while index < tag.endIndex, tag[index] != quote {
                        value.append(tag[index])
                        index = tag.index(after: index)
                    }
                    if index < tag.endIndex { index = tag.index(after: index) }
                    attributes[name.lowercased()] = value
                } else {
                    var value = ""
                    while index < tag.endIndex, !tag[index].isWhitespace {
                        value.append(tag[index])
                        index = tag.index(after: index)
                    }
                    attributes[name.lowercased()] = value
                }
            } else {
                attributes[name.lowercased()] = ""
            }
        }

        return attributes
    }

    static func postNumber(from href: String) -> PostNumber? {
        guard let marker = href.range(of: "#p") else { return nil }
        let digits = href[marker.upperBound...].prefix(while: { $0.isNumber })
        guard let value = Int(digits), value > 0 else { return nil }
        return PostNumber(value)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "&",
               let semicolon = text[index...].firstIndex(of: ";"),
               text.distance(from: index, to: semicolon) <= 12 {
                let body = String(text[text.index(after: index)..<semicolon])
                if let decoded = decodeEntity(body) {
                    result.append(decoded)
                    index = text.index(after: semicolon)
                    continue
                }
            }
            result.append(character)
            index = text.index(after: index)
        }

        return result
    }

    static func decodeEntity(_ entity: String) -> String? {
        switch entity.lowercased() {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#039", "#39": return "'"
        case "nbsp": return "\u{00A0}"
        default:
            break
        }

        let lowercased = entity.lowercased()
        if lowercased.hasPrefix("#x"), let value = UInt32(lowercased.dropFirst(2), radix: 16),
           let scalar = Unicode.Scalar(value) {
            return String(Character(scalar))
        }
        if lowercased.hasPrefix("#"), let value = UInt32(lowercased.dropFirst()),
           let scalar = Unicode.Scalar(value) {
            return String(Character(scalar))
        }
        return nil
    }
}
