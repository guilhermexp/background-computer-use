import Foundation

public struct TextChunkDTO: Codable, Sendable {
    public let text: String
    public let totalLength: Int
    public let rangeStart: Int
    public let rangeEnd: Int
    public let truncated: Bool

    public init(text: String, totalLength: Int, rangeStart: Int, rangeEnd: Int, truncated: Bool) {
        self.text = text
        self.totalLength = totalLength
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.truncated = truncated
    }
}

enum TextChunkerError: Error, CustomStringConvertible {
    case invalidRange(String)

    var description: String {
        switch self {
        case .invalidRange(let message):
            return message
        }
    }
}

enum TextChunker {
    static func chunk(_ text: String, offset: Int, length: Int) throws -> TextChunkDTO {
        guard offset >= 0 else {
            throw TextChunkerError.invalidRange("offset must be >= 0.")
        }
        guard length > 0 else {
            throw TextChunkerError.invalidRange("length must be > 0.")
        }

        let characters = Array(text)
        guard offset <= characters.count else {
            throw TextChunkerError.invalidRange("offset \(offset) is past the end of the text (\(characters.count) characters).")
        }

        let end = min(characters.count, offset + length)
        return TextChunkDTO(
            text: String(characters[offset..<end]),
            totalLength: characters.count,
            rangeStart: offset,
            rangeEnd: end,
            truncated: end < characters.count
        )
    }
}

public enum TextSelectionPositionDTO: String, Codable, Sendable {
    case select
    case before
    case after
}

enum TextSelectionPlannerError: Error, CustomStringConvertible {
    case invalidOccurrence
    case notFound(String)

    var description: String {
        switch self {
        case .invalidOccurrence:
            return "occurrence must be >= 1."
        case .notFound(let message):
            return message
        }
    }
}

enum TextSelectionPlanner {
    static func range(
        in value: String,
        query: String,
        occurrence: Int,
        position: TextSelectionPositionDTO
    ) throws -> CFRange {
        guard occurrence >= 1 else {
            throw TextSelectionPlannerError.invalidOccurrence
        }
        guard query.isEmpty == false else {
            throw TextSelectionPlannerError.notFound("query must not be empty.")
        }

        let nsValue = value as NSString
        var searchStart = 0
        var found = NSRange(location: NSNotFound, length: 0)
        for _ in 0..<occurrence {
            guard searchStart <= nsValue.length else {
                break
            }
            found = nsValue.range(
                of: query,
                options: [],
                range: NSRange(location: searchStart, length: nsValue.length - searchStart)
            )
            guard found.location != NSNotFound else {
                break
            }
            searchStart = found.location + 1
        }

        guard found.location != NSNotFound else {
            throw TextSelectionPlannerError.notFound("\"\(query)\" occurrence \(occurrence) was not found.")
        }

        switch position {
        case .select:
            return CFRange(location: found.location, length: found.length)
        case .before:
            return CFRange(location: found.location, length: 0)
        case .after:
            return CFRange(location: found.location + found.length, length: 0)
        }
    }
}
