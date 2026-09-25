import ImagePipeline
import SwiftUI

/// Remote image backed by `ImagePipeline`.
///
/// - Measures its own size and requests a bitmap at exactly that pixel size (downsampled).
/// - Checks the memory cache *synchronously during render*: recycled cells show the image in the
///   very first frame — no placeholder flicker when scrolling back.
/// - Loading is bound to `.task(id:)`, so scrolling a cell off-screen cancels its download.
/// - Fades in only for network loads, and never when Reduce Motion is on.
public struct RemoteImage: View {
    private let url: URL?
    private let contentMode: ContentMode
    private let pipeline: ImagePipeline

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded: LoadedImage?
    @State private var failed = false

    private struct LoadedImage: Equatable {
        let key: ImageRequest
        let image: UIImage
    }

    private struct LoadKey: Equatable {
        let url: URL?
        let size: CGSize
    }

    public init(_ url: URL?, contentMode: ContentMode = .fill, pipeline: ImagePipeline = .shared) {
        self.url = url
        self.contentMode = contentMode
        self.pipeline = pipeline
    }

    public var body: some View {
        GeometryReader { proxy in
            let request = makeRequest(size: proxy.size)
            ZStack {
                NovaColor.surfaceMuted
                if let image = image(for: request) {
                    // Aspect-fill draws outside its frame. `.clipped()` only clips *pixels*, so the
                    // overflow would still hit-test and inflate accessibility frames of the enclosing
                    // button (a tap on one tile could land on its neighbour). Hence the explicit
                    // clip + no hit testing + hidden from accessibility on the bitmap itself.
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                } else if failed {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(NovaColor.textTertiary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .task(id: LoadKey(url: url, size: proxy.size)) {
                await load(request)
            }
        }
        .accessibilityHidden(true) // Decorative; the enclosing control carries the label.
    }

    private func makeRequest(size: CGSize) -> ImageRequest? {
        guard let url, size.width > 0, size.height > 0 else { return nil }
        return ImageRequest(url: url, pointSize: size, scale: displayScale)
    }

    private func image(for request: ImageRequest?) -> UIImage? {
        guard let request else { return nil }
        if let loaded, loaded.key == request {
            return loaded.image
        }
        return pipeline.cachedImage(for: request)
    }

    private func load(_ request: ImageRequest?) async {
        guard let request, pipeline.cachedImage(for: request) == nil else { return }
        failed = false
        do {
            let image = try await pipeline.image(for: request)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                loaded = LoadedImage(key: request, image: image)
            }
        } catch is CancellationError {
            // Scrolled away — nothing to do.
        } catch {
            if !Task.isCancelled {
                failed = true
            }
        }
    }
}
