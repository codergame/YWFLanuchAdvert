import CryptoKit
import Foundation

struct RemoteAd: Decodable {
    var id: String
    var priority: Int
    var updatedAt: String?
    var startTime: String
    var endTime: String
    var packageUrl: String
    var packageMd5: String
    var layout: LayoutDocument

    enum CodingKeys: String, CodingKey {
        case id, priority, updatedAt, startTime, endTime, packageUrl, packageMd5, layout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .id) {
            id = text
        } else {
            id = String(try container.decode(Int64.self, forKey: .id))
        }
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        startTime = try container.decode(String.self, forKey: .startTime)
        endTime = try container.decode(String.self, forKey: .endTime)
        packageUrl = try container.decode(String.self, forKey: .packageUrl)
        packageMd5 = try container.decode(String.self, forKey: .packageMd5).lowercased()
        layout = try container.decode(LayoutDocument.self, forKey: .layout)
    }
}

struct ManifestFile: Decodable {
    var ads: [RemoteAd]
}

struct PartialMeta: Codable {
    var url: String
    var md5: String
    var etag: String?
    var total: Int64?
}

final class PackageStore {
    private let queue = DispatchQueue(label: "com.ywf.lanuchadvert.store")
    private let lock = NSLock()
    private let files = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var domain = ""
    private var appKey = "default"
    private var syncing = false
    private var syncAgain = false

    private var rootURL: URL {
        let base = files.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("YWFLanuchAdvert", isDirectory: true)
    }

    func sync(domain: String, appKey: String) {
        queue.async {
            self.domain = domain
            self.appKey = appKey
            if self.syncing {
                self.syncAgain = true
                return
            }
            self.syncing = true
            repeat {
                self.syncAgain = false
                self.performSync()
            } while self.syncAgain
            self.syncing = false
        }
    }

    func bestReadyAd(now: Date = Date()) -> (ad: RemoteAd, directory: URL)? {
        lock.lock()
        defer { lock.unlock() }
        guard let manifest = loadManifest() else { return nil }
        let matches = manifest.ads.filter { ad in
            Self.inWindow(ad, now: now) && self.isReadyUnlocked(ad)
        }
        guard let ad = matches.max(by: { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return (Self.time(lhs.updatedAt) ?? .distantPast) < (Self.time(rhs.updatedAt) ?? .distantPast)
        }) else { return nil }
        return (ad, unzippedURL(ad.id))
    }

    func report(adId: String, type: String) {
        queue.async {
            guard !self.domain.isEmpty, let url = URL(string: "\(self.domain)/api/v1/ads/\(adId)/events") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["type": type])
            URLSession.shared.dataTask(with: request).resume()
        }
    }

    private func performSync() {
        try? files.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fetched = fetchManifest()
        let manifest: ManifestFile
        if let fetched {
            if !saveManifest(fetched) { return }
            guard let parsed = decodeManifest(fetched) else { return }
            manifest = parsed
            removeMissing(ids: Set(parsed.ads.map(\.id)))
        } else if let existing = loadManifest() {
            manifest = existing
        } else {
            return
        }
        for ad in manifest.ads {
            ensurePackage(ad)
        }
    }

    private func fetchManifest() -> Data? {
        guard !domain.isEmpty, var components = URLComponents(string: "\(domain)/api/v1/ads") else { return nil }
        components.queryItems = [URLQueryItem(name: "appKey", value: appKey)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("YWFLanuchAdvert/0.1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let semaphore = DispatchSemaphore(value: 0)
        var body: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                body = data
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return body
    }

    private func ensurePackage(_ ad: RemoteAd) {
        guard let packageURL = URL(string: ad.packageUrl), Self.allowedPackageURL(packageURL) else { return }
        let directory = adDirectory(ad.id)
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent("package.zip.partial")
        let metaURL = directory.appendingPathComponent("package.meta.json")
        var meta = loadMeta(metaURL) ?? PartialMeta(url: ad.packageUrl, md5: ad.packageMd5, etag: nil, total: nil)
        if meta.url != ad.packageUrl || meta.md5 != ad.packageMd5 {
            clearPackage(ad.id)
            meta = PartialMeta(url: ad.packageUrl, md5: ad.packageMd5, etag: nil, total: nil)
            saveMeta(meta, url: metaURL)
        }
        if isReady(ad) { return }
        if let total = meta.total, total > 0, fileLength(partial) == total, finalize(partial, ad: ad) {
            return
        }
        let downloader = RangeDownloader()
        switch downloader.download(url: packageURL, partial: partial, metaURL: metaURL, meta: &meta) {
        case .complete:
            _ = finalize(partial, ad: ad)
        case .restart:
            try? files.removeItem(at: partial)
            meta.total = nil
            meta.etag = nil
            saveMeta(meta, url: metaURL)
            if RangeDownloader().download(url: packageURL, partial: partial, metaURL: metaURL, meta: &meta) == .complete {
                _ = finalize(partial, ad: ad)
            }
        case .interrupted:
            break
        }
    }

    private func finalize(_ partial: URL, ad: RemoteAd) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard fileDigest(partial) == ad.packageMd5.lowercased() else {
            try? files.removeItem(at: partial)
            return false
        }
        let directory = adDirectory(ad.id)
        let temporary = directory.appendingPathComponent("unzipped.tmp")
        let final = unzippedURL(ad.id)
        try? files.removeItem(at: temporary)
        do {
            try ZipExtractor.unzip(file: partial, to: temporary)
        } catch {
            try? files.removeItem(at: temporary)
            try? files.removeItem(at: partial)
            return false
        }
        if missingRefs(ad.layout, root: temporary) {
            try? files.removeItem(at: temporary)
            try? files.removeItem(at: partial)
            return false
        }
        try? files.removeItem(at: final)
        do {
            try files.moveItem(at: temporary, to: final)
        } catch {
            return false
        }
        try? files.removeItem(at: partial)
        let ready = directory.appendingPathComponent("ready")
        try? ad.packageMd5.lowercased().data(using: .utf8)?.write(to: ready, options: .atomic)
        return true
    }

    private func isReady(_ ad: RemoteAd) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isReadyUnlocked(ad)
    }

    private func isReadyUnlocked(_ ad: RemoteAd) -> Bool {
        let ready = adDirectory(ad.id).appendingPathComponent("ready")
        guard let text = try? String(contentsOf: ready, encoding: .utf8) else { return false }
        if text.trimmingCharacters(in: .whitespacesAndNewlines) != ad.packageMd5.lowercased() { return false }
        let root = unzippedURL(ad.id)
        var isDir: ObjCBool = false
        if !files.fileExists(atPath: root.path, isDirectory: &isDir) || !isDir.boolValue { return false }
        return !missingRefs(ad.layout, root: root)
    }

    private func missingRefs(_ layout: LayoutDocument, root: URL) -> Bool {
        for relative in zipRefs(layout.root) {
            let url = root.appendingPathComponent(relative)
            if !files.fileExists(atPath: url.path) { return true }
        }
        return false
    }

    private func zipRefs(_ node: LayoutNode) -> [String] {
        var refs: [String] = []
        if let src = node.src, src.hasPrefix("zip://") {
            refs.append(String(src.dropFirst("zip://".count)))
        }
        if node.source?.type == "zip", let path = node.source?.path, !path.isEmpty {
            refs.append(path.hasPrefix("zip://") ? String(path.dropFirst("zip://".count)) : path)
        }
        for child in node.children ?? [] {
            refs.append(contentsOf: zipRefs(child))
        }
        return refs
    }

    private func clearPackage(_ id: String) {
        let directory = adDirectory(id)
        for name in ["package.zip.partial", "package.meta.json", "ready"] {
            try? files.removeItem(at: directory.appendingPathComponent(name))
        }
        try? files.removeItem(at: unzippedURL(id))
        try? files.removeItem(at: directory.appendingPathComponent("unzipped.tmp"))
    }

    private func removeMissing(ids: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        guard let names = try? files.contentsOfDirectory(atPath: rootURL.path) else { return }
        for name in names where name != "manifest.json" && !ids.contains(name) {
            try? files.removeItem(at: rootURL.appendingPathComponent(name))
        }
    }

    private func adDirectory(_ id: String) -> URL {
        let safe = !id.isEmpty && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        let folder = safe ? id : Insecure.MD5.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent(folder, isDirectory: true)
    }

    private func unzippedURL(_ id: String) -> URL {
        adDirectory(id).appendingPathComponent("unzipped", isDirectory: true)
    }

    private func loadManifest() -> ManifestFile? {
        let url = rootURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodeManifest(data)
    }

    private func decodeManifest(_ data: Data) -> ManifestFile? {
        try? decoder.decode(ManifestFile.self, from: data)
    }

    private func saveManifest(_ data: Data) -> Bool {
        do {
            try data.write(to: rootURL.appendingPathComponent("manifest.json"), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func loadMeta(_ url: URL) -> PartialMeta? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(PartialMeta.self, from: data)
    }

    private func saveMeta(_ meta: PartialMeta, url: URL) {
        if let data = try? encoder.encode(meta) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func fileLength(_ url: URL) -> Int64 {
        guard let size = try? files.attributesOfItem(atPath: url.path)[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    private func fileDigest(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func inWindow(_ ad: RemoteAd, now: Date) -> Bool {
        guard let start = time(ad.startTime), let end = time(ad.endTime) else { return false }
        return now >= start && now <= end
    }

    private static func time(_ text: String?) -> Date? {
        guard let text = text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func allowedPackageURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        if scheme == "http" {
            let host = (url.host ?? "").lowercased()
            return host == "localhost" || host == "127.0.0.1" || host == "::1"
        }
        return false
    }
}

enum DownloadOutcome {
    case complete
    case interrupted
    case restart
}

final class RangeDownloader: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var handle: FileHandle?
    private var metaURL: URL?
    private var meta = PartialMeta(url: "", md5: "", etag: nil, total: nil)
    private var outcome = DownloadOutcome.interrupted
    private var settled = false
    private let semaphore = DispatchSemaphore(value: 0)
    private let encoder = JSONEncoder()

    func download(url: URL, partial: URL, metaURL: URL, meta: inout PartialMeta) -> DownloadOutcome {
        self.metaURL = metaURL
        self.meta = meta
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: partial.path) {
            fileManager.createFile(atPath: partial.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: partial) else { return .interrupted }
        self.handle = handle
        let offset = ((try? fileManager.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value) ?? 0
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("YWFLanuchAdvert/0.1.0", forHTTPHeaderField: "User-Agent")
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
            if let etag = meta.etag, !etag.isEmpty {
                request.setValue(etag, forHTTPHeaderField: "If-Range")
            }
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        session.dataTask(with: request).resume()
        semaphore.wait()
        meta = self.meta
        return outcome
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            finish(.interrupted)
            completionHandler(.cancel)
            return
        }
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            meta.etag = etag
        }
        if let header = http.value(forHTTPHeaderField: "Content-Range"), let total = Self.totalLength(header) {
            meta.total = total
        } else if http.statusCode == 200, let length = http.value(forHTTPHeaderField: "Content-Length"), let total = Int64(length) {
            meta.total = total
        }
        persistMeta()
        if http.statusCode == 206 {
            handle?.seekToEndOfFile()
            completionHandler(.allow)
            return
        }
        if http.statusCode == 200 {
            handle?.truncateFile(atOffset: 0)
            handle?.seek(toFileOffset: 0)
            completionHandler(.allow)
            return
        }
        if http.statusCode == 416 {
            let size = handle?.seekToEndOfFile() ?? 0
            if let total = meta.total, total > 0, Int64(size) == total {
                finish(.complete)
            } else {
                finish(.restart)
            }
            completionHandler(.cancel)
            return
        }
        finish(.interrupted)
        completionHandler(.cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handle?.write(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error == nil, let http = task.response as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 206 {
            let size = handle?.seekToEndOfFile() ?? 0
            if let total = meta.total, total > 0, Int64(size) != total {
                finish(.restart)
                return
            }
            finish(.complete)
            return
        }
        finish(.interrupted)
    }

    private func finish(_ outcome: DownloadOutcome) {
        if settled { return }
        settled = true
        self.outcome = outcome
        try? handle?.close()
        handle = nil
        session?.finishTasksAndInvalidate()
        session = nil
        semaphore.signal()
    }

    private func persistMeta() {
        guard let metaURL = metaURL, let data = try? encoder.encode(meta) else { return }
        try? data.write(to: metaURL, options: .atomic)
    }

    private static func totalLength(_ header: String) -> Int64? {
        guard let slash = header.lastIndex(of: "/") else { return nil }
        let raw = header[header.index(after: slash)...]
        if raw == "*" { return nil }
        return Int64(raw)
    }
}
