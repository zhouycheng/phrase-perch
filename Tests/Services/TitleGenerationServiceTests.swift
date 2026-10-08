import XCTest

@testable import PhrasePerch

final class TitleGenerationServiceTests: XCTestCase {
    func testLocalAddressesAndFullTitleValidation() throws {
        for address in ["http://localhost:8317/v1/", "http://127.0.0.1:1234/v1", "http://[::1]:8317/v1", "https://localhost/v1"] {
            XCTAssertFalse(try TitleGenerationService.baseURL(address).absoluteString.hasSuffix("/"))
        }
        for address in ["https://example.com/v1", "http://127.0.0.1.evil.test/v1", "http://127.1/v1",
            "file:///tmp/v1", "http://user:password@localhost/v1", "http://localhost/v1?key=test", "http://localhost:0/v1"] {
            XCTAssertThrowsError(try TitleGenerationService.baseURL(address))
        }
        XCTAssertEqual(try TitleGenerationService.cleanTitle("  “详细解释一下”\n"), "详细解释一下")
        XCTAssertEqual(try TitleGenerationService.cleanTitle("👩‍💻快速回复"), "👩‍💻快速回复")
        for invalid in ["", "“ ”", "标题\n解释", "标题\t正文", String(repeating: "字", count: 21)] {
            XCTAssertThrowsError(try TitleGenerationService.cleanTitle(invalid))
        }
    }

    func testModelDiscoveryAndGenerationUseUnauthenticatedCompatibleRequests() async throws {
        let service = StubTitleURLProtocol.service { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Key"))
            if request.url?.path == "/v1/models" {
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.timeoutInterval, 5)
                return (200, Data(#"{"data":[{"id":"model-b"},{"id":"model-a"},{"id":"model-b"}]}"#.utf8))
            }
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 30)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: StubTitleURLProtocol.body(request)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "model-a")
            XCTAssertEqual(body["stream"] as? Bool, false)
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages.last?["content"], "帮我解释这段代码")
            XCTAssertEqual(messages.last?["role"], "user")
            return (200, Data(#"{"choices":[{"message":{"content":"“代码解释”"},"finish_reason":"stop"}]}"#.utf8))
        }
        let models = try await service.models(at: Preferences.defaultTitleAPIBaseURL)
        XCTAssertEqual(models, ["model-a", "model-b"])
        let title = try await service.generateTitle(for: "帮我解释这段代码", address: Preferences.defaultTitleAPIBaseURL, model: "model-a")
        XCTAssertEqual(title, "代码解释")
    }

    func testErrorsAndMalformedResponsesRemainActionable() async throws {
        for (status, expected) in [(401, "鉴权"), (403, "鉴权"), (404, "不可用"), (429, "频繁"), (503, "HTTP 503")] {
            let service = StubTitleURLProtocol.service { _ in (status, Data()) }
            do {
                _ = try await service.generateTitle(for: "正文", address: Preferences.defaultTitleAPIBaseURL, model: "test")
                XCTFail("Expected HTTP error")
            } catch { XCTAssertTrue(error.localizedDescription.contains(expected)) }
        }
        for data in [Data("bad".utf8), Data(#"{"choices":[]}"#.utf8),
            Data(#"{"choices":[{"message":{"content":"标题"},"finish_reason":"length"}]}"#.utf8)] {
            let service = StubTitleURLProtocol.service { _ in (200, data) }
            do {
                _ = try await service.generateTitle(for: "正文", address: Preferences.defaultTitleAPIBaseURL, model: "test")
                XCTFail("Expected malformed response error")
            } catch { XCTAssertTrue(error.localizedDescription.contains("完整标题")) }
        }
        for (code, expected) in [(URLError.Code.cannotConnectToHost, "已启动"), (.timedOut, "超时")] {
            let service = StubTitleURLProtocol.service { _ in throw URLError(code) }
            do {
                _ = try await service.models(at: Preferences.defaultTitleAPIBaseURL)
                XCTFail("Expected connection error")
            } catch { XCTAssertTrue(error.localizedDescription.contains(expected)) }
        }
        let empty = StubTitleURLProtocol.service { _ in (200, Data(#"{"data":[]}"#.utf8)) }
        do {
            _ = try await empty.models(at: Preferences.defaultTitleAPIBaseURL)
            XCTFail("Expected empty model error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("可用模型")) }
    }
}
