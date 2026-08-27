import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct PIDWindowDiscoveryTests {
    @Test
    func listWindowsDecodesOnlyAPositivePID() throws {
        let request = try JSONDecoder().decode(
            ListWindowsRequest.self,
            from: Data(#"{"pid":25268}"#.utf8)
        )
        #expect(request.pid == 25268)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ListWindowsRequest.self,
                from: Data(#"{"app":"Google Chrome"}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ListWindowsRequest.self,
                from: Data(#"{"pid":0}"#.utf8)
            )
        }
    }

    @Test
    func routeDocumentsPIDAndOmitsLegacyAppSelector() throws {
        let route = try #require(
            RouteRegistry.publicRoutes().first { $0.id == RouteID.listWindows.rawValue }
        )
        let fields = try #require(route.request?.fields)

        #expect(fields.contains { $0.name == "pid" && $0.type == "integer" })
        #expect(fields.contains { $0.name == "app" } == false)
    }
}
