import AppKit
@testable import BackgroundComputerUse
import Testing

@Suite(.serialized)
struct PasteRouteTests {
    @Test @MainActor
    func snapshotRestoresEveryItemTypeAndByte() throws {
        let pasteboard = NSPasteboard(name: .init("bcu-paste-test-\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let customType = NSPasteboard.PasteboardType("com.example.bcu.binary")
        let first = NSPasteboardItem()
        first.setString("plain", forType: .string)
        first.setData(Data("<b>plain</b>".utf8), forType: .html)
        first.setData(Data([0x00, 0x01, 0xFE, 0xFF]), forType: customType)
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)
        #expect(pasteboard.writeObjects([first, second]))

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        #expect(snapshot.restore(to: pasteboard))

        let restored = try #require(pasteboard.pasteboardItems)
        #expect(restored.count == 2)
        #expect(restored[0].string(forType: .string) == "plain")
        #expect(restored[0].data(forType: .html) == Data("<b>plain</b>".utf8))
        #expect(restored[0].data(forType: customType) == Data([0x00, 0x01, 0xFE, 0xFF]))
        #expect(restored[1].string(forType: .string) == "second")
    }

    @Test @MainActor
    func markdownPublishesMarkdownAndPlainText() throws {
        let pasteboard = NSPasteboard(name: .init("bcu-paste-test-\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }

        #expect(PasteboardPayload.write("**bold**", format: .markdown, to: pasteboard))

        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(item.string(forType: .string) == "**bold**")
        #expect(item.string(forType: .init("net.daringfireball.markdown")) == "**bold**")
    }

    @Test @MainActor
    func htmlPublishesHTMLAndReadablePlainText() throws {
        let pasteboard = NSPasteboard(name: .init("bcu-paste-test-\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }

        #expect(PasteboardPayload.write("<strong>Bold</strong> text", format: .html, to: pasteboard))

        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(item.string(forType: .html) == "<strong>Bold</strong> text")
        #expect(item.string(forType: .string) == "Bold text")
    }

    @Test @MainActor
    func failedDispatchStillRestoresCompletePasteboard() throws {
        let pasteboard = NSPasteboard(name: .init("bcu-paste-test-\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let customType = NSPasteboard.PasteboardType("com.example.original")
        let original = NSPasteboardItem()
        original.setString("original", forType: .string)
        original.setData(Data([0xCA, 0xFE]), forType: customType)
        #expect(pasteboard.writeObjects([original]))

        let result = PasteTransaction.perform(
            content: "temporary",
            format: .text,
            pasteboard: pasteboard,
            dispatch: { false }
        )

        #expect(result.payloadWritten)
        #expect(result.dispatchSucceeded == false)
        #expect(result.restoreSucceeded)
        let restored = try #require(pasteboard.pasteboardItems?.first)
        #expect(restored.string(forType: .string) == "original")
        #expect(restored.data(forType: customType) == Data([0xCA, 0xFE]))
    }

    @Test
    func routeDocumentsStrictPasteContract() throws {
        let route = try #require(RouteRegistry.publicRoutes().first { $0.id == "paste" })
        let fields = try #require(route.request?.fields)

        #expect(fields.contains { $0.name == "window" && $0.required })
        #expect(fields.contains { $0.name == "target" && $0.required })
        #expect(fields.contains { $0.name == "content" && $0.required })
        #expect(fields.contains { $0.name == "format" && $0.type == "text | markdown | html" })
    }

    @Test
    func clipboardFallbackRequiresConfirmedFocusOnTheExactTarget() {
        #expect(PasteFallbackFocusPolicy.allows(isFocused: true, foregroundPreserved: true))
        #expect(PasteFallbackFocusPolicy.allows(isFocused: false, foregroundPreserved: true) == false)
        #expect(PasteFallbackFocusPolicy.allows(isFocused: nil, foregroundPreserved: true) == false)
        #expect(PasteFallbackFocusPolicy.allows(isFocused: true, foregroundPreserved: false) == false)
    }
}
