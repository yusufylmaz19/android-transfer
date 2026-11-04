import AppKit
import CoreImage.CIFilterBuiltins
import Foundation
import Network

struct WirelessEntry: Codable, Identifiable {
    let name: String
    let isDirectory: Bool
    let isHidden: Bool?
    var id: String { name }
}

struct WirelessLocation: Codable, Identifiable {
    let id: String
    let name: String
}

struct WirelessList: Codable {
    let entries: [WirelessEntry]
}

struct WirelessTransferItem: Identifiable {
    let id = UUID()
    let name: String
    var detail = "Sırada"
    var progress = 0.0
    var finished = false
    var failed = false
}

enum WirelessError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let value) = self { return value }
        return nil
    }
}

enum WirelessCode {
    static func image(for value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let image = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let representation = NSCIImageRep(ciImage: image)
        let result = NSImage(size: representation.size)
        result.addRepresentation(representation)
        return result
    }
}

@MainActor final class WirelessModel: ObservableObject {
    @Published var active = false
    @Published var peerURL = ""
    @Published var peerToken = ""
    @Published var peerLocations: [WirelessLocation] = []
    @Published var selectedLocation = ""
    @Published var path = ""
    @Published var entries: [WirelessEntry] = []
    @Published var selectedNames: Set<String> = []
    @Published var showHidden = false
    @Published var status = "Kablosuz paylaşımı başlatın veya telefonun kodunu tarayın."
    @Published var busy = false
    @Published var transferItems: [WirelessTransferItem] = []
    @Published var showTransferSummary = false
    private var transferBatch = 0
    @Published var localAddress = ""
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "android-transfer-wireless", qos: .userInitiated)
    private let port: UInt16 = 46732

    var qrValue: String {
        guard active, !localAddress.isEmpty else { return "" }
        return "androidtransfer://pair?host=\(localAddress)&port=\(port)&token=\(token)"
    }

    var localLocations: [(String, URL)] {
        #if DEBUG
        if let testRoot = ProcessInfo.processInfo.environment["ANDROID_TRANSFER_TEST_ROOT"] {
            return [("test", URL(fileURLWithPath: testRoot, isDirectory: true))]
        }
        #endif
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [("home", home)]
    }

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { [weak self] connection in
                self?.receive(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.active = true
                        self.localAddress = Self.localIPv4() ?? ""
                        self.status = self.localAddress.isEmpty ? "Yerel IP bulunamadı." : "Paylaşım hazır: \(self.localAddress):\(self.port)"
                    case .failed(let error):
                        self.active = false
                        self.status = error.localizedDescription
                    case .cancelled:
                        self.active = false
                    default: break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch { status = error.localizedDescription }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        active = false
        localAddress = ""
        status = "Kablosuz paylaşım durduruldu."
    }

    private nonisolated static func localIPv4() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let head = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        var current: UnsafeMutablePointer<ifaddrs>? = head
        var addresses: [(String, String)] = []
        while let item = current {
            let value = item.pointee
            if value.ifa_addr?.pointee.sa_family == UInt8(AF_INET),
               (value.ifa_flags & UInt32(IFF_UP)) != 0,
               (value.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               let address = value.ifa_addr {
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var copy = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                _ = inet_ntop(AF_INET, &copy, &buffer, socklen_t(INET_ADDRSTRLEN))
                let addressString = String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if isPrivateIPv4(addressString) {
                    addresses.append((String(cString: value.ifa_name), addressString))
                }
            }
            current = value.ifa_next
        }
        return addresses.first(where: { $0.0 == "en0" })?.1 ?? addresses.first?.1
    }

    private nonisolated func receive(_ connection: NWConnection) {
        guard case let .hostPort(host, _) = connection.endpoint,
              Self.isPrivateIPv4(String(describing: host)) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        readRequest(connection, received: Data())
    }

    private nonisolated static func isPrivateIPv4(_ value: String) -> Bool {
        let bytes = value.split(separator: ".").compactMap { UInt8($0) }
        guard bytes.count == 4 else { return false }
        return bytes[0] == 127 || bytes[0] == 10 ||
            (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
            (bytes[0] == 192 && bytes[1] == 168)
    }

    private nonisolated func readRequest(_ connection: NWConnection, received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self, error == nil, let data else { connection.cancel(); return }
            let message = received + data
            guard message.count <= 64 * 1024 * 1024 else { connection.cancel(); return }
            if let marker = message.range(of: Data("\r\n\r\n".utf8)),
               let header = String(data: message[..<marker.lowerBound], encoding: .utf8) {
                let headerLines = header.components(separatedBy: "\r\n")
                if headerLines.contains(where: { $0.lowercased().hasPrefix("transfer-encoding:") && $0.lowercased().contains("chunked") }) {
                    if let body = Self.decodeChunks(Data(message[marker.upperBound...])) {
                        let normalized = Data(message[..<marker.upperBound]) + body
                        Task { @MainActor in
                            let reply = self.handle(normalized)
                            connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
                        }
                        return
                    }
                    if complete { connection.cancel() }
                    else { self.readRequest(connection, received: message) }
                    return
                }
                let lengthLine = headerLines.first(where: { $0.lowercased().hasPrefix("content-length:") })
                if header.hasPrefix("PUT "), lengthLine == nil {
                    Task { @MainActor in
                        connection.send(content: self.errorResponse(411, "Dosya boyutu belirtilmedi."), completion: .contentProcessed { _ in connection.cancel() })
                    }
                    return
                }
                let length = lengthLine.flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
                guard length >= 0, length <= 64 * 1024 * 1024 else { connection.cancel(); return }
                if message.count >= marker.upperBound + length {
                    Task { @MainActor in
                        let reply = self.handle(message)
                        connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
                    }
                    return
                }
            }
            if complete { connection.cancel() }
            else { self.readRequest(connection, received: message) }
        }
    }

    private nonisolated static func decodeChunks(_ body: Data) -> Data? {
        let crlf = Data([13, 10])
        var cursor = 0
        var output = Data()
        while cursor < body.count {
            guard let lineEnd = body.range(of: crlf, in: cursor..<body.count),
                  let sizeText = String(data: body[cursor..<lineEnd.lowerBound], encoding: .ascii)?
                    .split(separator: ";", maxSplits: 1).first,
                  let size = Int(sizeText, radix: 16), size >= 0 else { return nil }
            cursor = lineEnd.upperBound
            if size == 0 {
                guard body.count >= cursor + 2 else { return nil }
                return body[cursor] == 13 && body[cursor + 1] == 10 ? output : nil
            }
            guard size <= 64 * 1024 * 1024,
                  body.count >= cursor + size + 2,
                  body[cursor + size] == 13, body[cursor + size + 1] == 10 else { return nil }
            output.append(body[cursor..<(cursor + size)])
            cursor += size + 2
        }
        return nil
    }

    private func response(_ code: Int, _ data: Data, type: String = "application/json") -> Data {
        let message = switch code {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 409: "Conflict"
        case 411: "Length Required"
        case 413: "Content Too Large"
        default: "Error"
        }
        let header = "HTTP/1.1 \(code) \(message)\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + data
    }

    private func errorResponse(_ code: Int, _ message: String) -> Data {
        response(code, (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data())
    }

    private func handle(_ data: Data) -> Data {
        guard let marker = data.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: data[..<marker.lowerBound], encoding: .utf8),
              let first = header.components(separatedBy: "\r\n").first else {
            return response(400, Data())
        }
        let lines = header.components(separatedBy: "\r\n")
        let authorization = lines.first(where: { $0.lowercased().hasPrefix("x-transfer-token:") })?
            .split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
        guard authorization == token else { return response(401, Data()) }
        let parts = first.split(separator: " ")
        guard parts.count >= 2, let components = URLComponents(string: String(parts[1])) else { return response(400, Data()) }
        let method = String(parts[0])
        let endpoint = components.path
        let query = Dictionary((components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
        if endpoint == "/roots", method == "GET" {
            let roots = localLocations.map { WirelessLocation(id: $0.0, name: $0.1.lastPathComponent) }
            return response(200, (try? JSONEncoder().encode(roots)) ?? Data("[]".utf8))
        }
        guard let rootName = query["root"], let root = localLocations.first(where: { $0.0 == rootName })?.1,
              let relative = query["path"], !relative.hasPrefix("/"),
              !relative.split(separator: "/").contains("..") else { return response(400, Data()) }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let file = canonicalRoot.appendingPathComponent(relative).standardizedFileURL
        let resolved = file.resolvingSymlinksInPath()
        guard file.path == canonicalRoot.path || file.path.hasPrefix(canonicalRoot.path + "/"),
              resolved.path == canonicalRoot.path || resolved.path.hasPrefix(canonicalRoot.path + "/") else { return response(400, Data()) }
        if endpoint == "/list", method == "GET" {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: file.path) else { return response(404, Data()) }
            let entries = names.sorted().filter { name in
                let candidate = file.appendingPathComponent(name).resolvingSymlinksInPath()
                return candidate.path.hasPrefix(canonicalRoot.path + "/")
            }.map { name -> WirelessEntry in
                let candidate = file.appendingPathComponent(name)
                var directory: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &directory)
                let hidden = name.hasPrefix(".") || ((try? candidate.resourceValues(forKeys: [.isHiddenKey]).isHidden) == true)
                return WirelessEntry(name: name, isDirectory: directory.boolValue, isHidden: hidden)
            }
            return response(200, (try? JSONEncoder().encode(WirelessList(entries: entries))) ?? Data())
        }
        if endpoint == "/file", method == "GET" {
            guard FileManager.default.fileExists(atPath: file.path) else { return errorResponse(404, "Dosya artık bu klasörde yok. Listeyi yenileyin.") }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let size = attributes[.size] as? NSNumber else { return errorResponse(403, "Dosya bilgisi okunamadı.") }
            guard size.int64Value <= 64 * 1024 * 1024 else { return errorResponse(413, "64 MB üzeri dosyalar henüz desteklenmiyor.") }
            guard let content = try? Data(contentsOf: file) else { return errorResponse(403, "Dosya okunamadı; macOS dosya erişim iznini kontrol edin.") }
            return response(200, content, type: "application/octet-stream")
        }
        if endpoint == "/file", method == "PUT" {
            guard !FileManager.default.fileExists(atPath: file.path) else { return errorResponse(409, "Mac'te aynı adla dosya var.") }
            guard FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path) else { return errorResponse(404, "Hedef klasör bulunamadı.") }
            let body = data[marker.upperBound...]
            guard (try? Data(body).write(to: file, options: .withoutOverwriting)) != nil else { return errorResponse(403, "Dosya Mac'e yazılamadı; klasör iznini kontrol edin.") }
            return response(200, Data("{}".utf8))
        }
        return response(404, Data())
    }

    func connect(_ code: String) async {
        guard let components = URLComponents(string: code.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "androidtransfer", components.host == "pair",
              let host = components.queryItems?.first(where: { $0.name == "host" })?.value,
              let port = components.queryItems?.first(where: { $0.name == "port" })?.value,
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              let number = UInt16(port) else { status = "Geçersiz bağlantı kodu."; return }
        peerURL = "http://\(host):\(number)"
        peerToken = token
        path = ""
        entries = []
        selectedNames = []
        await loadRoots()
    }

    private func request(_ endpoint: String, method: String = "GET", body: Data? = nil,
                         transferIndex: Int? = nil) async throws -> Data {
        guard let url = URL(string: peerURL + endpoint) else { throw WirelessError.message("Bağlantı adresi geçersiz.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(peerToken, forHTTPHeaderField: "X-Transfer-Token")
        request.timeoutInterval = 120
        if let body { request.httpBody = body; request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type") }
        let data: Data
        let response: URLResponse
        if let transferIndex {
            let client = WirelessTransferClient(uploading: method == "PUT") { [weak self] completed, total in
                Task { @MainActor in self?.updateTransfer(transferIndex, completed: completed, total: total) }
            }
            (data, response) = try await client.perform(request)
        } else {
            (data, response) = try await URLSession.shared.data(for: request)
        }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
            throw WirelessError.message("\(detail ?? "Karşı cihaz isteği kabul etmedi.") (\(statusCode))")
        }
        return data
    }

    private func updateTransfer(_ index: Int, completed: Int64, total: Int64) {
        guard transferItems.indices.contains(index), !transferItems[index].finished else { return }
        if total > 0 {
            transferItems[index].progress = min(0.98, Double(completed) / Double(total))
            transferItems[index].detail = completed >= total ? "Karşı cihazda kaydediliyor" :
                "\(ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
        } else {
            transferItems[index].detail = "\(ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)) aktarıldı"
        }
    }

    private func finishTransfer(_ index: Int, error: Error? = nil) {
        guard transferItems.indices.contains(index) else { return }
        transferItems[index].finished = true
        transferItems[index].failed = error != nil
        transferItems[index].progress = 1
        transferItems[index].detail = error?.localizedDescription ?? "Tamamlandı"
    }

    private func endpoint(_ action: String, path: String) -> String {
        var components = URLComponents()
        components.path = action
        components.queryItems = [URLQueryItem(name: "root", value: selectedLocation), URLQueryItem(name: "path", value: path)]
        return components.string ?? action
    }

    func loadRoots() async {
        do {
            peerLocations = try JSONDecoder().decode([WirelessLocation].self, from: await request("/roots"))
            selectedLocation = peerLocations.first?.id ?? ""
            await loadDirectory()
        } catch {
            peerLocations = []
            entries = []
            status = error.localizedDescription
        }
    }

    func loadDirectory() async {
        guard !selectedLocation.isEmpty else { return }
        do {
            let result = try JSONDecoder().decode(WirelessList.self, from: await request(endpoint("/list", path: path)))
            entries = showHidden ? result.entries : result.entries.filter { $0.isHidden != true && !$0.name.hasPrefix(".") }
            selectedNames = []
            status = "\(entries.count) öğe listelendi."
        } catch { entries = []; selectedNames = []; status = error.localizedDescription }
    }

    func open(_ entry: WirelessEntry) async {
        guard entry.isDirectory else { return }
        path = path.isEmpty ? entry.name : path + "/" + entry.name
        await loadDirectory()
    }

    func toggleHidden() async {
        showHidden.toggle()
        if !showHidden && path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
            path = ""
        }
        await loadDirectory()
    }

    private func hideTransferSummary(after batch: Int) {
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard batch == transferBatch, !busy else { return }
            showTransferSummary = false
        }
    }

    func goUp() async {
        guard !path.isEmpty else { return }
        path = (path as NSString).deletingLastPathComponent
        if path == "." { path = "" }
        await loadDirectory()
    }

    func downloadSelected() async {
        guard !selectedNames.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        busy = true
        defer { busy = false }
        let names = selectedNames.sorted()
        transferBatch += 1
        let batch = transferBatch
        transferItems = names.map { WirelessTransferItem(name: $0) }
        showTransferSummary = true
        for (index, name) in names.enumerated() {
            do {
                guard entries.first(where: { $0.name == name })?.isDirectory == false else {
                    throw WirelessError.message("Klasör aktarımı henüz desteklenmiyor.")
                }
                let target = folder.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: target.path) else { throw WirelessError.message("Hedefte aynı ad var: \(name)") }
                let relative = path.isEmpty ? name : path + "/" + name
                transferItems[index].detail = "İndiriliyor"
                let data = try await request(endpoint("/file", path: relative), transferIndex: index)
                let temporary = folder.appendingPathComponent(".\(UUID().uuidString).transfer-part")
                do {
                    try data.write(to: temporary, options: .atomic)
                    guard !FileManager.default.fileExists(atPath: target.path) else {
                        throw WirelessError.message("Hedefte aynı ad var: \(name)")
                    }
                    try FileManager.default.moveItem(at: temporary, to: target)
                } catch {
                    try? FileManager.default.removeItem(at: temporary)
                    throw error
                }
                finishTransfer(index)
            } catch {
                finishTransfer(index, error: error)
            }
        }
        let failed = transferItems.filter(\.failed).count
        status = "Mac'e indirme: \(names.count - failed) tamamlandı, \(failed) hata."
        hideTransferSummary(after: batch)
    }

    func upload() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        busy = true
        defer { busy = false }
        let files = panel.urls
        transferBatch += 1
        let batch = transferBatch
        transferItems = files.map { WirelessTransferItem(name: $0.lastPathComponent) }
        showTransferSummary = true
        for (index, file) in files.enumerated() {
            do {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 64 * 1024 * 1024 else {
                    throw WirelessError.message("Bu sürümde 64 MB üzeri dosya aktarılamıyor: \(file.lastPathComponent)")
                }
                let relative = path.isEmpty ? file.lastPathComponent : path + "/" + file.lastPathComponent
                transferItems[index].detail = "Gönderiliyor"
                _ = try await request(endpoint("/file", path: relative), method: "PUT",
                                      body: Data(contentsOf: file), transferIndex: index)
                finishTransfer(index)
            } catch {
                finishTransfer(index, error: error)
            }
        }
        await loadDirectory()
        let failed = transferItems.filter(\.failed).count
        status = "Telefona gönderme: \(files.count - failed) tamamlandı, \(failed) hata. Hedef: /storage/emulated/0\(path.isEmpty ? "" : "/" + path)"
        hideTransferSummary(after: batch)
    }
}
