import Foundation

/// Minimal seam over the network so the API client and token service can be unit-tested
/// with a stub instead of hitting the network. `URLSession` conforms in production.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

public enum HTTPError: Error, Equatable {
    case status(Int, body: String)
    case nonHTTPResponse
    case invalidURL
}
