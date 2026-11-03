import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ADBTransfer {
    static func pull(adb: URL, device: String, source: String, target: URL) throws {
        let process = Process()
        process.executableURL = adb
        process.arguments = ["-s", device, "pull", source, target.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: target)
            throw ADBError.message(String(decoding: data, as: UTF8.self))
        }
    }
}

struct PhoneItem: Identifiable, Hashable {
    let name: String
    let isDirectory: Bool
    var id: String { name }
}

enum ADBError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

@MainActor final class TransferModel: ObservableObject {
    private let storageRoot = "/storage/emulated/0"
    @Published var devices: [String] = []
    @Published var selectedDevice = ""
    @Published var path = "/storage/emulated/0"
    @Published var items: [PhoneItem] = []
    @Published var selection: Set<String> = []
    @Published var destination: URL? = nil
    @Published var status = "Telefonu USB ile bağlayıp USB hata ayıklamaya izin verin."
    @Published var busy = false
    private var pendingUploads: [(urls: [URL], directory: String, move: Bool)] = []

    var adb: URL? {
        let candidates = [
            ProcessInfo.processInfo.environment["ANDROID_HOME"].map { "\($0)/platform-tools/adb" },
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ].compactMap { $0 }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    private func command(_ args: [String]) async throws -> String {
        guard let adb else { throw ADBError.message("ADB bulunamadı. Android SDK Platform Tools kurun.") }
        return try await Task.detached {
            let process = Process()
            process.executableURL = adb
            process.arguments = args
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else { throw ADBError.message(text.isEmpty ? "ADB işlemi başarısız." : text) }
            return text
        }.value
    }

    private func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func refreshDevices() async {
        await checkConnection(reload: true)
    }

    func toggleSelection(_ name: String) {
        if selection.contains(name) { selection.remove(name) }
        else { selection.insert(name) }
    }

    private func clearDisconnectedState(_ message: String) {
        devices = []
        selectedDevice = ""
        path = storageRoot
        items = []
        selection = []
        status = message
    }

    func checkConnection(reload: Bool = false) async {
        do {
            let output = try await command(["devices", "-l"])
            let lines = output.split(separator: "\n").dropFirst().map(String.init)
            let connected = lines.compactMap { line -> String? in
                let parts = line.split(whereSeparator: \.isWhitespace)
                return parts.count >= 2 && parts[1] == "device" && line.contains("usb:") ? String(parts[0]) : nil
            }
            let previous = selectedDevice
            devices = connected
            if !devices.contains(selectedDevice) { selectedDevice = devices.first ?? "" }
            let unauthorized = lines.contains { $0.contains("unauthorized") }
            if selectedDevice.isEmpty {
                clearDisconnectedState(unauthorized ? "Telefon ekranındaki USB hata ayıklama iznini onaylayın." : "USB bağlantısı kesildi. Telefonu yeniden bağlayın.")
            } else if previous != selectedDevice {
                path = storageRoot
                items = []
                selection = []
                await loadDirectory()
            } else if reload {
                await loadDirectory()
            }
        } catch { clearDisconnectedState(error.localizedDescription) }
    }

    func loadDirectory() async {
        guard !selectedDevice.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let device = selectedDevice
            let directory = path
            // One ADB round trip lists children and directory names.
            let separator = "__ANDROID_TRANSFER_DIRS_9D7B__"
            let folder = quoted(directory)
            let script = "find \(folder) -mindepth 1 -maxdepth 1 -print; echo \(separator); find \(folder) -mindepth 1 -maxdepth 1 -type d -print"
            let output = try await command(["-s", device, "shell", script])
            guard selectedDevice == device, path == directory else { return }
            let sections = output.components(separatedBy: separator)
            guard sections.count == 2 else { throw ADBError.message("Klasör listesi okunamadı.") }
            let prefix = directory == "/" ? "/" : directory + "/"
            let lines = sections[0].split(separator: "\n").map(String.init)
            let paths = lines.filter { $0.hasPrefix(prefix) }
            let names = paths.map { String($0.dropFirst(prefix.count)) }
                .filter { !$0.isEmpty && !$0.contains("/") }
            let directories = Set(sections[1].split(separator: "\n").map(String.init))
            items = names.map { PhoneItem(name: $0, isDirectory: directories.contains(prefix + $0)) }
            items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            selection = []
            status = "\(items.count) öğe listelendi."
        } catch {
            if !selectedDevice.isEmpty { items = []; selection = []; status = error.localizedDescription }
        }
    }

    func open(_ item: PhoneItem) async {
        guard item.isDirectory else { return }
        path += "/" + item.name
        await loadDirectory()
    }

    func goUp() async {
        guard path != storageRoot else { return }
        path = (path as NSString).deletingLastPathComponent
        await loadDirectory()
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK { destination = panel.url }
    }

    private func destinationFromPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func copy(_ item: PhoneItem) async {
        guard let adb, !selectedDevice.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let cache = FileManager.default.temporaryDirectory.appendingPathComponent("AndroidTransferClipboard", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let target = cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let file = target.appendingPathComponent(item.name)
            status = "Panoya hazırlanıyor: \(item.name)"
            let source = path + "/" + item.name
            let device = selectedDevice
            try await Task.detached { try ADBTransfer.pull(adb: adb, device: device, source: source, target: file) }.value
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([file as NSURL])
            status = "Kopyalandı. Finder'da hedef klasöre yapıştırın: \(item.name)"
        } catch { status = error.localizedDescription }
    }

    func move(_ item: PhoneItem) async {
        guard let adb, !selectedDevice.isEmpty, let folder = destinationFromPanel() else { return }
        let target = folder.appendingPathComponent(item.name)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            status = "Hedefte aynı ad var; taşıma yapılmadı: \(item.name)"
            return
        }
        busy = true
        defer { busy = false }
        let source = path + "/" + item.name
        let device = selectedDevice
        do {
            status = "Taşınıyor: \(item.name)"
            try await Task.detached { try ADBTransfer.pull(adb: adb, device: device, source: source, target: target) }.value
            let remove = item.isDirectory ? "rm -r -- \(quoted(source))" : "rm -- \(quoted(source))"
            _ = try await command(["-s", device, "shell", remove])
            status = "Mac'e taşındı: \(item.name)"
            await loadDirectory()
        } catch { status = "Taşıma tamamlanamadı. Mac'teki kopyayı kontrol edin: \(error.localizedDescription)" }
    }

    func delete(_ item: PhoneItem) async {
        guard !selectedDevice.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let source = path + "/" + item.name
            let remove = item.isDirectory ? "rm -r -- \(quoted(source))" : "rm -- \(quoted(source))"
            _ = try await command(["-s", selectedDevice, "shell", remove])
            status = "Telefondan silindi: \(item.name)"
            await loadDirectory()
        } catch { status = error.localizedDescription }
    }

    func dragProvider(for item: PhoneItem) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = item.name
        guard let adb, !selectedDevice.isEmpty else { return provider }
        let source = path + "/" + item.name
        let device = selectedDevice
        let type = item.isDirectory ? UTType.folder.identifier : (UTType(filenameExtension: (item.name as NSString).pathExtension)?.identifier ?? UTType.data.identifier)
        provider.registerFileRepresentation(forTypeIdentifier: type, fileOptions: [], visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 1)
            DispatchQueue.global(qos: .userInitiated).async {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AndroidTransferDrag-\(UUID().uuidString)", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let file = folder.appendingPathComponent(item.name)
                    try ADBTransfer.pull(adb: adb, device: device, source: source, target: file)
                    progress.completedUnitCount = 1
                    completion(file, false, nil)
                } catch { completion(nil, false, error) }
            }
            return progress
        }
        return provider
    }

    func chooseMacFiles(move: Bool = false) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Telefona aktarılacak dosya veya klasörleri seçin"
        guard panel.runModal() == .OK else { return }
        await upload(panel.urls, to: path, move: move)
    }

    func pasteFromFinder(to remoteDirectory: String? = nil) async {
        let urls = (NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        guard !urls.isEmpty else {
            status = "Finder'da dosya veya klasör kopyalayıp yeniden deneyin."
            return
        }
        await upload(urls, to: remoteDirectory ?? path, move: false)
    }

    func acceptDrop(_ providers: [NSItemProvider], to remoteDirectory: String) -> Bool {
        let fileProviders = providers.filter { $0.canLoadObject(ofClass: NSURL.self) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: NSURL.self) { object, error in
                let filePath = (object as? URL)?.path
                let errorText = error?.localizedDescription
                Task { @MainActor in
                    if let filePath {
                        let url = URL(fileURLWithPath: filePath)
                        await self.upload([url], to: remoteDirectory, move: false)
                    } else {
                        self.status = errorText ?? "Bırakılan dosya okunamadı."
                    }
                }
            }
        }
        return true
    }

    func upload(_ urls: [URL], to remoteDirectory: String, move: Bool) async {
        guard !selectedDevice.isEmpty else { return }
        if busy {
            pendingUploads.append((urls, remoteDirectory, move))
            return
        }
        busy = true
        defer {
            busy = false
            if !pendingUploads.isEmpty {
                let next = pendingUploads.removeFirst()
                Task { await upload(next.urls, to: next.directory, move: next.move) }
            }
        }
        do {
            for (index, url) in urls.enumerated() {
                guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
                    throw ADBError.message("Mac dosyası bulunamadı: \(url.lastPathComponent)")
                }
                let remote = remoteDirectory + "/" + url.lastPathComponent
                let exists = try await command(["-s", selectedDevice, "shell", "test -e \(quoted(remote)) && echo yes || echo no"])
                guard exists == "no" else {
                    throw ADBError.message("Telefonda aynı ad var; üzerine yazılmadı: \(url.lastPathComponent)")
                }
                status = "Telefona aktarılıyor: \(index + 1)/\(urls.count) — \(url.lastPathComponent)"
                _ = try await command(["-s", selectedDevice, "push", url.path, remote])
                if move {
                    var trashed: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                }
            }
            status = "\(urls.count) öğe telefona \(move ? "taşındı" : "kopyalandı")."
            if remoteDirectory == path { await loadDirectory() }
        } catch { status = error.localizedDescription }
    }

    func transfer() async {
        guard let destination, !selectedDevice.isEmpty, !selection.isEmpty else { return }
        busy = true
        defer { busy = false }
        let names = selection.sorted()
        do {
            for (index, name) in names.enumerated() {
                let source = path + "/" + name
                let target = destination.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: target.path) else {
                    throw ADBError.message("\(name) hedef klasörde zaten var. Üzerine yazılmadı.")
                }
                status = "Aktarılıyor: \(index + 1)/\(names.count) — \(name)"
                do {
                    _ = try await command(["-s", selectedDevice, "pull", source, target.path])
                } catch {
                    if FileManager.default.fileExists(atPath: target.path) {
                        try? FileManager.default.removeItem(at: target)
                    }
                    throw error
                }
            }
            status = "\(names.count) öğe aktarıldı: \(destination.path)"
        } catch { status = error.localizedDescription }
    }
}

private enum Theme {
    static let canvas = Color(red: 0.055, green: 0.075, blue: 0.115)
    static let rail = Color(red: 0.09, green: 0.12, blue: 0.18)
    static let surface = Color(red: 0.12, green: 0.155, blue: 0.22)
    static let line = Color.white.opacity(0.10)
    static let text = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let muted = Color(red: 0.61, green: 0.67, blue: 0.75)
    static let coral = Color(red: 1.0, green: 0.43, blue: 0.36)
    static let mint = Color(red: 0.37, green: 0.88, blue: 0.80)
    static let blue = Color(red: 0.46, green: 0.67, blue: 1.0)
}

struct ContentView: View {
    @StateObject private var model = TransferModel()
    @State private var pendingDeletion: PhoneItem?
    @State private var dropTargeted = false

    private var isConnected: Bool { !model.selectedDevice.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView { sidebar }
                .frame(width: 300)
                .background(Theme.rail)
            Rectangle().fill(Theme.line).frame(width: 1)
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
        }
        .foregroundStyle(Theme.text)
        .frame(minWidth: 980, minHeight: 670)
        .preferredColorScheme(.dark)
        .task {
            await model.refreshDevices()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                await model.checkConnection()
            }
        }
        .alert("Telefondan silinsin mi?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Sil", role: .destructive) {
                if let item = pendingDeletion { Task { await model.delete(item) } }
                pendingDeletion = nil
            }
            Button("Vazgeç", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("\(pendingDeletion?.name ?? "Bu öğe") ve içeriği telefondan kalıcı olarak silinecek.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 44, height: 44)
                    .background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ANDROID").font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                    Text("TRANSFER").font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                }
            }
            .padding(.bottom, 44)

            sectionLabel("BAĞLANTI")
            HStack(spacing: 9) {
                Circle().fill(isConnected ? Theme.mint : Theme.coral).frame(width: 8, height: 8)
                Text(isConnected ? "USB cihazı bağlı" : "Cihaz bekleniyor")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 12)

            if isConnected {
                Picker("Cihaz", selection: $model.selectedDevice) {
                    ForEach(model.devices, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            }
            Button { Task { await model.refreshDevices() } } label: {
                Label("Cihazları Yenile", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.muted)
            .padding(.top, 14)
            .disabled(model.busy)

            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 30)
            sectionLabel("MAC → ANDROID")
            Text("Dosyaları telefona gönder")
                .font(.system(size: 18, weight: .bold))
                .padding(.top, 7)
            Text("Finder'dan bırak veya dosya seç.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Theme.mint)
                Text("BURAYA BIRAK")
                    .font(.system(size: 12, weight: .bold)).tracking(1.4)
                Text("Telefondaki açık klasöre aktarılır")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(16)
            .background(dropTargeted ? Theme.mint.opacity(0.16) : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(dropTargeted ? Theme.mint : Theme.line, style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
            .padding(.top, 18)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                model.acceptDrop(providers, to: model.path)
            }

            Button { Task { await model.chooseMacFiles() } } label: {
                Label("Mac'ten Dosya Seç", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(Theme.canvas)
            .font(.system(size: 13, weight: .bold))
            .padding(.top, 14)
            .disabled(model.busy || !isConnected)

            HStack(spacing: 14) {
                Button("Yapıştır") { Task { await model.pasteFromFinder() } }
                Button("Mac'ten Taşı") { Task { await model.chooseMacFiles(move: true) } }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.mint)
            .padding(.top, 15)
            .disabled(model.busy || !isConnected)
            Spacer(minLength: 20)
            Text("YEREL • USB ÜZERİNDEN")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Theme.muted)
        }
        .padding(26)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("DOSYA YÖNETİCİSİ")
                    Text("Telefon dosyaları")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                }
                Spacer()
                Text("\(model.items.count) ÖĞE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 22)
            }
            .padding(.bottom, 23)

            HStack(spacing: 10) {
                Button { Task { await model.goUp() } } label: {
                    Image(systemName: "arrow.up")
                        .frame(width: 35, height: 35)
                }
                .keyboardShortcut(.delete, modifiers: [])
                .help("Üst klasör (Backspace)")
                .disabled(model.busy || model.path == "/storage/emulated/0")
                Text(model.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button { Task { await model.loadDirectory() } } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .disabled(model.busy || !isConnected)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 13)
            .frame(height: 49)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 15)

            fileBrowser
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            transferFooter
                .padding(.top, 18)
            if model.busy {
                ProgressView().progressViewStyle(.linear).tint(Theme.mint)
                    .padding(.top, 13)
            }
            HStack(spacing: 8) {
                Circle().fill(model.busy ? Theme.coral : Theme.mint).frame(width: 6, height: 6)
                Text(model.status)
                    .lineLimit(2)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .padding(.top, 15)
        }
        .padding(28)
    }

    private var fileBrowser: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.items) { item in
                    fileRow(item)
                    if item.id != model.items.last?.id {
                        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 58)
                    }
                }
            }
        }
        .overlay {
            if model.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: isConnected ? "folder" : "cable.connector.slash")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Theme.blue)
                    Text(isConnected ? "Bu klasör boş" : "Telefonu USB ile bağlayın")
                        .font(.system(size: 15, weight: .semibold))
                    Text(isConnected ? "Başka bir klasöre göz atabilirsiniz." : "Bağlandığında dosyalar burada görünecek.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
        }
        .background(Theme.rail, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
    }

    private func fileRow(_ item: PhoneItem) -> some View {
        let selected = model.selection.contains(item.name)
        return HStack(spacing: 13) {
            Button { model.toggleSelection(item.name) } label: {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Theme.mint : Theme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name) seçimini değiştir")
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 16))
                .foregroundStyle(item.isDirectory ? Theme.blue : Theme.coral)
                .frame(width: 33, height: 33)
                .background((item.isDirectory ? Theme.blue : Theme.coral).opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if item.isDirectory { Task { await model.open(item) } }
                }
            Spacer(minLength: 8)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .frame(width: 28, height: 30)
                .help("Finder'a sürükle")
                .onDrag { model.dragProvider(for: item) }
            if item.isDirectory {
                Button { Task { await model.open(item) } } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 20, height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 51)
        .background(selected ? Theme.mint.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Kopyala (Finder'a Yapıştır)") { Task { await model.copy(item) } }
            Button("Kes / Mac'e Taşı…") { Task { await model.move(item) } }
            if item.isDirectory {
                Divider()
                Button("Bu Klasöre Yapıştır") { Task { await model.pasteFromFinder(to: model.path + "/" + item.name) } }
            }
            Divider()
            Button("Telefondan Sil…", role: .destructive) { pendingDeletion = item }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard item.isDirectory else { return false }
            return model.acceptDrop(providers, to: model.path + "/" + item.name)
        }
    }

    private var transferFooter: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.coral)
                .frame(width: 38, height: 38)
                .background(Theme.coral.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text("ANDROID → MAC")
                    .font(.system(size: 10, weight: .bold)).tracking(1.3)
                    .foregroundStyle(Theme.coral)
                Text(model.destination?.path ?? "Hedef klasör seçilmedi")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            Button("Hedef Seç") { model.chooseDestination() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
            Button { Task { await model.transfer() } } label: {
                Text("Mac'e Aktar")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 19)
                    .padding(.vertical, 11)
                    .background(Theme.coral, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(Theme.canvas)
            }
            .buttonStyle(.plain)
            .disabled(model.busy || model.selection.isEmpty || model.destination == nil)
            .opacity(model.busy || model.selection.isEmpty || model.destination == nil ? 0.45 : 1)
        }
        .padding(15)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.8)
            .foregroundStyle(Theme.muted)
    }
}

@main struct AndroidTransferApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
