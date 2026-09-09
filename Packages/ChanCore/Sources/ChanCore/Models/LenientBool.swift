import Foundation

/// Decodes a boolean from any of the shapes 4chan actually uses.
///
/// The API is inconsistent: `ws_board` is `1`/`0`, while other endpoints send real
/// JSON booleans. Strict `Bool` decoding rejects the numeric form, so every
/// boolean field routes through this.
struct LenientBool: Decodable {
    let value: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int != 0
        } else if let string = try? container.decode(String.self) {
            value = string == "1" || string.lowercased() == "true"
        } else {
            value = false
        }
    }
}
