import Foundation

final class WirelessTransferClient: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let uploading: Bool
    private let progress: @Sendable (Int64, Int64) -> Void
    private var session: URLSession?
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var response: URLResponse?
    private var received = Data()

    init(uploading: Bool, progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.uploading = uploading
        self.progress = progress
    }

    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            self.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received.append(data)
        if !uploading {
            progress(Int64(received.count), response?.expectedContentLength ?? -1)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        if uploading { progress(totalBytesSent, totalBytesExpectedToSend) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            continuation = nil
            self.session?.finishTasksAndInvalidate()
            self.session = nil
        }
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else if let response {
            continuation.resume(returning: (received, response))
        } else {
            continuation.resume(throwing: URLError(.badServerResponse))
        }
    }
}
