import Foundation
@testable import ImagePipeline
import Testing
import UIKit

@Suite("ImagePipeline")
struct ImagePipelineTests {
    let unsplash = URL(string: "https://images.unsplash.com/photo-1?auto=format&q=75")!

    @Test("CDN width follows the drawn pixel size, bucketed")
    func cdnBuckets() throws {
        let thumb = ImageRequest(url: unsplash, pointSize: CGSize(width: 150, height: 200), scale: 3)
        let resolved = try #require(URLComponents(url: ImageCDN.resolvedURL(for: thumb), resolvingAgainstBaseURL: false))
        #expect(resolved.queryItems?.first { $0.name == "w" }?.value == "480")
        #expect(resolved.queryItems?.contains { $0.name == "auto" } == true, "Existing CDN params are preserved")
    }

    @Test("Non-CDN hosts are left untouched")
    func otherHosts() throws {
        let url = try #require(URL(string: "https://example.com/a.jpg"))
        #expect(ImageCDN.resolvedURL(for: ImageRequest(url: url, pointSize: CGSize(width: 100, height: 100), scale: 2)) == url)
    }

    @Test("Cache keys differ by size bucket but not by tiny size changes")
    func cacheKeys() {
        let small = ImageRequest(url: unsplash, pointSize: CGSize(width: 150, height: 200), scale: 3)
        let nearlySmall = ImageRequest(url: unsplash, pointSize: CGSize(width: 152, height: 200), scale: 3)
        let big = ImageRequest(url: unsplash, pointSize: CGSize(width: 390, height: 520), scale: 3)
        #expect(small.cacheKey == nearlySmall.cacheKey)
        #expect(small.cacheKey != big.cacheKey)
    }

    @Test("Downsampling decodes at the target size, not the source size")
    func downsample() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000), format: .init(for: .init(displayScale: 1)))
        let data = try #require(renderer.image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }.pngData())

        let image = try Downsampler.downsample(data, to: CGSize(width: 400, height: 200))
        #expect(max(image.size.width, image.size.height) == 400)
    }

    @Test("Garbage data throws instead of crashing")
    func undecodable() {
        #expect(throws: Downsampler.Failure.self) { try Downsampler.downsample(Data("nope".utf8), to: nil) }
    }

    @Test("Memory cache is keyed and synchronous")
    func memoryCache() throws {
        let cache = MemoryCache()
        let image = try #require(UIImage(systemName: "star"))
        cache["k"] = image
        #expect(cache["k"] === image)
        cache["k"] = nil
        #expect(cache["k"] == nil)
    }
}
