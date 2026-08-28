import AppKit
import Foundation

struct PasteboardSnapshot {
    private struct Representation {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private let items: [[Representation]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { Representation(type: type, data: $0) }
            }
        }
        return PasteboardSnapshot(items: items)
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        guard items.isEmpty == false else { return true }
        let restored = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: representation.type)
            }
            return item
        }
        return pasteboard.writeObjects(restored)
    }
}

enum PasteboardPayload {
    private static let markdownType = NSPasteboard.PasteboardType("net.daringfireball.markdown")

    @discardableResult
    static func write(
        _ content: String,
        format: PasteFormatDTO,
        to pasteboard: NSPasteboard
    ) -> Bool {
        let item = NSPasteboardItem()
        switch format {
        case .text:
            item.setString(content, forType: .string)

        case .markdown:
            item.setString(content, forType: .string)
            item.setString(content, forType: markdownType)

        case .html:
            guard let data = content.data(using: .utf8),
                  let attributed = try? NSAttributedString(
                      data: data,
                      options: [
                          .documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue,
                      ],
                      documentAttributes: nil
                  )
            else {
                return false
            }
            item.setString(content, forType: .html)
            item.setString(attributed.string, forType: .string)
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    static func plainText(_ content: String, format: PasteFormatDTO) -> String? {
        switch format {
        case .text, .markdown:
            return content
        case .html:
            guard let data = content.data(using: .utf8),
                  let attributed = try? NSAttributedString(
                      data: data,
                      options: [
                          .documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue,
                      ],
                      documentAttributes: nil
                  )
            else {
                return nil
            }
            return attributed.string
        }
    }
}
