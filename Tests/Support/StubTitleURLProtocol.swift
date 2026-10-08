import Foundation

@testable import PhrasePerch

final class StubTitleURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var handlers: [String: Handler] = [:]
        func set(_ id: String, handler: @escaping Handler) {
            lock.lock()
            defer { lock.unlock() }
            handlers[id] = handler
        }
        func get(_ id: String) -> Handler? {
            lock.lock()
            defer { lock.unlock() }
            return handlers[id]
        }
    }
    private static let registry = Registry()
    private let stopLock = NSLock()
    private var stopped = false

    static func service(_ handler: @escaping Handler) -> TitleGenerationService {
        let id = UUID().uuidString
        registry.set(id, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        configuration.httpAdditionalHeaders = ["X-Title-Test": id]
        return TitleGenerationService(session: URLSession(configuration: configuration))
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Title-Test"), let handler = Self.registry.get(id) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data) = try handler(request)
            stopLock.lock()
            let active = !stopped
            stopLock.unlock()
            guard active else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {
        stopLock.lock()
        stopped = true
        stopLock.unlock()
    }
    static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
