import Foundation
import ImageIO
import NovaCore
import UIKit

/// What to load and at what size. Two cells showing the same URL at different sizes are different
/// cache entries — a 170 pt grid thumbnail must never decode the 4000 px original.
public struct ImageRequest: Hashable, Sendable {
    public let url: URL
    /// Target size in **pixels** (points × display scale). `nil` = full resolution.
    public let pixelSize: CGSize?

    public init(url: URL, pointSize: CGSize?, scale: CGFloat) {
        self.url = url
        pixelSize = pointSize.map { CGSize(width: ($0.width * scale).rounded(.up), height: ($0.height * scale).rounded(.up)) }
    }

    /// Cache key = source URL + size bucket, so near-identical sizes share one decoded bitmap but a
    /// full-screen gallery image never reuses a blurry thumbnail.
    var cacheKey: String {
        "\(url.absoluteString)#\(pixelSize.map { String(Int(ImageCDN.bucket(for: $0))) } ?? "full")"
    }
}

/// The image loading stack used by every `RemoteImage`.
///
/// Performance properties (each one measurable in Instruments):
/// 1. **Memory cache hit is synchronous** (`cachedImage(for:)`) → cells re-appearing while
///    scrolling render in the same frame with no placeholder flash.
/// 2. **Request coalescing** — ten cells asking for one URL share one download + one decode.
/// 3. **CDN width buckets** — we ask the image CDN for ~the pixel width we draw, typically
///    cutting bytes 5-10× versus the original.
/// 4. **ImageIO downsampling off the main thread** — decodes straight into a bitmap of the target
///    size (`kCGImageSourceShouldCacheImmediately`), so the main thread never pays JPEG decode.
/// 5. **Disk cache** via a dedicated `URLCache` (HTTP semantics, survives relaunch).
/// 6. **Cancellation** — when every requester of an image goes away the download is cancelled.
public actor ImagePipeline {
    public static let shared = ImagePipeline()

    private let session: URLSession
    private let memoryCache: MemoryCache
    private var inFlight: [String: InFlight] = [:]

    private final class InFlight {
        let task: Task<UIImage, any Error>
        var waiters = 0

        init(task: Task<UIImage, any Error>) {
            self.task = task
        }
    }

    public init(memoryCache: MemoryCache = MemoryCache(), diskCapacity: Int = 250 * 1024 * 1024) {
        self.memoryCache = memoryCache
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: diskCapacity, directory: Self.cacheDirectory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "ImagePipeline")
    }

    /// Synchronous, non-isolated memory lookup. Safe because `MemoryCache` wraps `NSCache`.
    public nonisolated func cachedImage(for request: ImageRequest) -> UIImage? {
        memoryCache[request.cacheKey]
    }

    public func image(for request: ImageRequest) async throws -> UIImage {
        let key = request.cacheKey
        if let cached = memoryCache[key] {
            return cached
        }

        let entry: InFlight
        if let existing = inFlight[key] {
            entry = existing
        } else {
            let session = session
            let memoryCache = memoryCache
            entry = InFlight(task: Task(priority: .userInitiated) {
                let image = try await Self.fetchAndDecode(request, session: session)
                memoryCache[key] = image
                return image
            })
            inFlight[key] = entry
        }

        entry.waiters += 1
        defer {
            entry.waiters -= 1
            if entry.waiters == 0 {
                inFlight[key] = nil
            }
        }

        return try await withTaskCancellationHandler {
            try await entry.task.value
        } onCancel: {
            Task { await self.cancelIfUnwanted(key: key) }
        }
    }

    /// Warms the cache for images about to scroll on screen. Low priority, bounded concurrency.
    public func prefetch(_ requests: [ImageRequest]) async {
        await withTaskGroup(of: Void.self) { group in
            for request in requests.prefix(12) where memoryCache[request.cacheKey] == nil {
                group.addTask(priority: .utility) { _ = try? await self.image(for: request) }
            }
        }
    }

    public func removeAll() {
        memoryCache.removeAll()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    private func cancelIfUnwanted(key: String) {
        guard let entry = inFlight[key], entry.waiters <= 1 else { return }
        entry.task.cancel()
    }

    // MARK: Fetch + decode (runs on the cooperative pool, never the main actor)

    private static func fetchAndDecode(_ request: ImageRequest, session: URLSession) async throws -> UIImage {
        let url = ImageCDN.resolvedURL(for: request)
        let data = try await Perf.measure("Image.Fetch") {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? true else {
                throw URLError(.badServerResponse)
            }
            return data
        }
        try Task.checkCancellation()
        return try Perf.measureSync("Image.Decode") {
            try Downsampler.downsample(data, to: request.pixelSize)
        }
    }
}

/// Thread-safe memory cache. `NSCache` is documented thread-safe and auto-evicts under memory
/// pressure, which is exactly why it is wrapped rather than re-implemented with a lock.
public final class MemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()

    public init(totalCostLimit: Int = 80 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = 400
    }

    public subscript(key: String) -> UIImage? {
        get { cache.object(forKey: key as NSString) }
        set {
            if let newValue {
                cache.setObject(newValue, forKey: key as NSString, cost: newValue.decodedByteCount)
            } else {
                cache.removeObject(forKey: key as NSString)
            }
        }
    }

    public func removeAll() {
        cache.removeAllObjects()
    }
}

public enum Downsampler {
    public enum Failure: Error { case undecodable }

    /// Decodes `data` directly at `pixelSize` using ImageIO. Memory for a 170×220 pt @3x cell is
    /// ~1.3 MB instead of ~48 MB for a 4000×3000 original.
    public static func downsample(_ data: Data, to pixelSize: CGSize?) throws -> UIImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { throw Failure.undecodable }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true, // decode now, on this background thread
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let pixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(pixelSize.width, pixelSize.height)
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.undecodable
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Image CDN URL rewriting (imgix / Unsplash / Cloudinary style `w=` parameter).
public enum ImageCDN {
    /// Width buckets keep the CDN cache hit-rate high and our memory cache compact.
    static let widthBuckets: [CGFloat] = [160, 320, 480, 640, 828, 1080, 1440]

    /// Smallest bucket that covers the drawn size (assumes ~4:3 portrait product imagery).
    static func bucket(for pixelSize: CGSize) -> CGFloat {
        let target = max(pixelSize.width, pixelSize.height * 0.75)
        return widthBuckets.first { $0 >= target } ?? widthBuckets[widthBuckets.count - 1]
    }

    public static func resolvedURL(for request: ImageRequest) -> URL {
        guard let pixelSize = request.pixelSize,
              var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
              components.host?.contains("unsplash.com") == true
        else { return request.url }
        let bucket = bucket(for: pixelSize)
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "w" }
        items.append(URLQueryItem(name: "w", value: String(Int(bucket))))
        components.queryItems = items
        return components.url ?? request.url
    }
}

extension UIImage {
    var decodedByteCount: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
