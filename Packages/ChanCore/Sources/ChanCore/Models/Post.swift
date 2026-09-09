import Foundation

/// A single post, exactly as the API describes it.
///
/// Decoding is hand-written because the API mixes shapes: timestamps are Unix
/// seconds, `id` is the poster ID (not a primary key), `sub`/`com` are `subject`/
/// `commentHTML`, and only OP posts carry thread statistics.
public struct Post: Codable, Hashable, Sendable, Identifiable {
    public let no: PostNumber
    public let resto: PostNumber
    public let time: Date
    public let name: String?
    public let trip: String?
    public let posterID: String?
    public let capcode: String?
    public let country: String?
    public let countryName: String?
    public let boardFlag: String?
    public let flagName: String?
    public let subject: String?
    public let commentHTML: String?
    public let since4pass: Int?

    // Attachment (present when the post has a file)
    public let tim: Int?
    public let filename: String?
    public let ext: String?
    public let fileSize: Int?
    public let md5: String?
    public let width: Int?
    public let height: Int?
    public let thumbnailWidth: Int?
    public let thumbnailHeight: Int?
    public let isSpoiler: Bool?
    public let customSpoiler: Int?
    public let hasMidSizeImage: Bool?
    public let isFileDeleted: Bool?

    // Thread statistics (OP only)
    public let replies: Int?
    public let images: Int?
    public let lastModified: Date?
    public let isSticky: Bool?
    public let isClosed: Bool?
    public let isArchived: Bool?
    public let isBumpLimit: Bool?
    public let isImageLimit: Bool?
    public let uniqueIPs: Int?
    public let semanticURL: String?

    public var id: PostNumber { no }
    public var isOP: Bool { resto.value == 0 }

    public var attachment: Attachment? {
        guard let tim, let ext, let filename else { return nil }
        return Attachment(
            tim: tim,
            filename: filename,
            ext: ext,
            size: fileSize ?? 0,
            md5: md5,
            width: width ?? 0,
            height: height ?? 0,
            thumbnailWidth: thumbnailWidth ?? 0,
            thumbnailHeight: thumbnailHeight ?? 0,
            isSpoiler: isSpoiler ?? false,
            customSpoiler: customSpoiler ?? 0,
            hasMidSizeImage: hasMidSizeImage ?? false,
            isDeleted: isFileDeleted ?? false
        )
    }

    public init(
        no: PostNumber,
        resto: PostNumber = 0,
        time: Date,
        name: String? = nil,
        trip: String? = nil,
        posterID: String? = nil,
        capcode: String? = nil,
        country: String? = nil,
        countryName: String? = nil,
        boardFlag: String? = nil,
        flagName: String? = nil,
        subject: String? = nil,
        commentHTML: String? = nil,
        since4pass: Int? = nil,
        tim: Int? = nil,
        filename: String? = nil,
        ext: String? = nil,
        fileSize: Int? = nil,
        md5: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        thumbnailWidth: Int? = nil,
        thumbnailHeight: Int? = nil,
        isSpoiler: Bool? = nil,
        customSpoiler: Int? = nil,
        hasMidSizeImage: Bool? = nil,
        isFileDeleted: Bool? = nil,
        replies: Int? = nil,
        images: Int? = nil,
        lastModified: Date? = nil,
        isSticky: Bool? = nil,
        isClosed: Bool? = nil,
        isArchived: Bool? = nil,
        isBumpLimit: Bool? = nil,
        isImageLimit: Bool? = nil,
        uniqueIPs: Int? = nil,
        semanticURL: String? = nil
    ) {
        self.no = no
        self.resto = resto
        self.time = time
        self.name = name
        self.trip = trip
        self.posterID = posterID
        self.capcode = capcode
        self.country = country
        self.countryName = countryName
        self.boardFlag = boardFlag
        self.flagName = flagName
        self.subject = subject
        self.commentHTML = commentHTML
        self.since4pass = since4pass
        self.tim = tim
        self.filename = filename
        self.ext = ext
        self.fileSize = fileSize
        self.md5 = md5
        self.width = width
        self.height = height
        self.thumbnailWidth = thumbnailWidth
        self.thumbnailHeight = thumbnailHeight
        self.isSpoiler = isSpoiler
        self.customSpoiler = customSpoiler
        self.hasMidSizeImage = hasMidSizeImage
        self.isFileDeleted = isFileDeleted
        self.replies = replies
        self.images = images
        self.lastModified = lastModified
        self.isSticky = isSticky
        self.isClosed = isClosed
        self.isArchived = isArchived
        self.isBumpLimit = isBumpLimit
        self.isImageLimit = isImageLimit
        self.uniqueIPs = uniqueIPs
        self.semanticURL = semanticURL
    }

    private enum CodingKeys: String, CodingKey {
        case no, resto, time, name, trip, capcode, country, tim, filename, ext, md5
        case fsize, w, h, spoiler, replies, images, sticky, closed, archived, bumplimit, imagelimit
        case posterID = "id"
        case countryName = "country_name"
        case boardFlag = "board_flag"
        case flagName = "flag_name"
        case subject = "sub"
        case commentHTML = "com"
        case since4pass
        case thumbnailWidth = "tn_w"
        case thumbnailHeight = "tn_h"
        case customSpoiler = "custom_spoiler"
        case hasMidSizeImage = "m_img"
        case isFileDeleted = "filedeleted"
        case lastModified = "last_modified"
        case uniqueIPs = "unique_ips"
        case semanticURL = "semantic_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        no = PostNumber(try c.decode(Int.self, forKey: .no))
        resto = PostNumber(try c.decodeIfPresent(Int.self, forKey: .resto) ?? 0)
        time = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .time))

        name = try c.decodeIfPresent(String.self, forKey: .name)
        trip = try c.decodeIfPresent(String.self, forKey: .trip)
        posterID = try c.decodeIfPresent(String.self, forKey: .posterID)
        capcode = try c.decodeIfPresent(String.self, forKey: .capcode)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        countryName = try c.decodeIfPresent(String.self, forKey: .countryName)
        boardFlag = try c.decodeIfPresent(String.self, forKey: .boardFlag)
        flagName = try c.decodeIfPresent(String.self, forKey: .flagName)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        commentHTML = try c.decodeIfPresent(String.self, forKey: .commentHTML)
        since4pass = try c.decodeIfPresent(Int.self, forKey: .since4pass)

        tim = try c.decodeIfPresent(Int.self, forKey: .tim)
        filename = try c.decodeIfPresent(String.self, forKey: .filename)
        ext = try c.decodeIfPresent(String.self, forKey: .ext)
        fileSize = try c.decodeIfPresent(Int.self, forKey: .fsize)
        md5 = try c.decodeIfPresent(String.self, forKey: .md5)
        width = try c.decodeIfPresent(Int.self, forKey: .w)
        height = try c.decodeIfPresent(Int.self, forKey: .h)
        thumbnailWidth = try c.decodeIfPresent(Int.self, forKey: .thumbnailWidth)
        thumbnailHeight = try c.decodeIfPresent(Int.self, forKey: .thumbnailHeight)
        isSpoiler = try c.decodeIfPresent(LenientBool.self, forKey: .spoiler)?.value
        customSpoiler = try c.decodeIfPresent(Int.self, forKey: .customSpoiler)
        hasMidSizeImage = try c.decodeIfPresent(LenientBool.self, forKey: .hasMidSizeImage)?.value
        isFileDeleted = try c.decodeIfPresent(LenientBool.self, forKey: .isFileDeleted)?.value

        replies = try c.decodeIfPresent(Int.self, forKey: .replies)
        images = try c.decodeIfPresent(Int.self, forKey: .images)
        if let modified = try c.decodeIfPresent(Double.self, forKey: .lastModified) {
            lastModified = Date(timeIntervalSince1970: modified)
        } else {
            lastModified = nil
        }
        isSticky = try c.decodeIfPresent(LenientBool.self, forKey: .sticky)?.value
        isClosed = try c.decodeIfPresent(LenientBool.self, forKey: .closed)?.value
        isArchived = try c.decodeIfPresent(LenientBool.self, forKey: .archived)?.value
        isBumpLimit = try c.decodeIfPresent(LenientBool.self, forKey: .bumplimit)?.value
        isImageLimit = try c.decodeIfPresent(LenientBool.self, forKey: .imagelimit)?.value
        uniqueIPs = try c.decodeIfPresent(Int.self, forKey: .uniqueIPs)
        semanticURL = try c.decodeIfPresent(String.self, forKey: .semanticURL)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(no.value, forKey: .no)
        try c.encode(resto.value, forKey: .resto)
        try c.encode(time.timeIntervalSince1970, forKey: .time)

        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(trip, forKey: .trip)
        try c.encodeIfPresent(posterID, forKey: .posterID)
        try c.encodeIfPresent(capcode, forKey: .capcode)
        try c.encodeIfPresent(country, forKey: .country)
        try c.encodeIfPresent(countryName, forKey: .countryName)
        try c.encodeIfPresent(boardFlag, forKey: .boardFlag)
        try c.encodeIfPresent(flagName, forKey: .flagName)
        try c.encodeIfPresent(subject, forKey: .subject)
        try c.encodeIfPresent(commentHTML, forKey: .commentHTML)
        try c.encodeIfPresent(since4pass, forKey: .since4pass)

        try c.encodeIfPresent(tim, forKey: .tim)
        try c.encodeIfPresent(filename, forKey: .filename)
        try c.encodeIfPresent(ext, forKey: .ext)
        try c.encodeIfPresent(fileSize, forKey: .fsize)
        try c.encodeIfPresent(md5, forKey: .md5)
        try c.encodeIfPresent(width, forKey: .w)
        try c.encodeIfPresent(height, forKey: .h)
        try c.encodeIfPresent(thumbnailWidth, forKey: .thumbnailWidth)
        try c.encodeIfPresent(thumbnailHeight, forKey: .thumbnailHeight)
        try c.encodeIfPresent(isSpoiler, forKey: .spoiler)
        try c.encodeIfPresent(customSpoiler, forKey: .customSpoiler)
        try c.encodeIfPresent(hasMidSizeImage, forKey: .hasMidSizeImage)
        try c.encodeIfPresent(isFileDeleted, forKey: .isFileDeleted)

        try c.encodeIfPresent(replies, forKey: .replies)
        try c.encodeIfPresent(images, forKey: .images)
        try c.encodeIfPresent(lastModified?.timeIntervalSince1970, forKey: .lastModified)
        try c.encodeIfPresent(isSticky, forKey: .sticky)
        try c.encodeIfPresent(isClosed, forKey: .closed)
        try c.encodeIfPresent(isArchived, forKey: .archived)
        try c.encodeIfPresent(isBumpLimit, forKey: .bumplimit)
        try c.encodeIfPresent(isImageLimit, forKey: .imagelimit)
        try c.encodeIfPresent(uniqueIPs, forKey: .uniqueIPs)
        try c.encodeIfPresent(semanticURL, forKey: .semanticURL)
    }
}

/// The file attached to a post, normalized into something the media layer can load.
public struct Attachment: Hashable, Sendable {
    public let tim: Int
    public let filename: String
    public let ext: String
    public let size: Int
    public let md5: String?
    public let width: Int
    public let height: Int
    public let thumbnailWidth: Int
    public let thumbnailHeight: Int
    public let isSpoiler: Bool
    public let customSpoiler: Int
    /// True when 4chan generated the ≤1024 px `{tim}m.jpg` preview.
    public let hasMidSizeImage: Bool
    public let isDeleted: Bool

    public var aspectRatio: Double {
        guard height > 0 else { return 1 }
        return Double(width) / Double(height)
    }

    public var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "webp"].contains(ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    }

    public var isVideo: Bool {
        ["webm", "mp4"].contains(ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    }

    public var isAnimated: Bool {
        ext.lowercased().contains("gif")
    }
}
