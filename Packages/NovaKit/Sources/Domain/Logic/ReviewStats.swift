import Foundation

/// Rating histogram for the reviews header ("4.8 out of 5", 5★ 72 % …).
public struct ReviewStats: Equatable, Sendable {
    public let average: Double
    public let total: Int
    /// Share of reviews per star (1...5), 0...1.
    public let distribution: [Int: Double]

    public init(average: Double, total: Int, distribution: [Int: Double]) {
        self.average = average
        self.total = total
        self.distribution = distribution
    }

    /// Computes stats locally from a list (used when the server omits the aggregate).
    public init(reviews: [Review]) {
        total = reviews.count
        guard !reviews.isEmpty else {
            average = 0
            distribution = Dictionary(uniqueKeysWithValues: (1 ... 5).map { ($0, 0) })
            return
        }
        let sum = reviews.reduce(0) { $0 + $1.rating }
        average = (Double(sum) / Double(reviews.count) * 10).rounded() / 10
        var counts = [Int: Int]()
        for review in reviews {
            counts[min(max(review.rating, 1), 5), default: 0] += 1
        }
        distribution = Dictionary(uniqueKeysWithValues: (1 ... 5).map { star in
            (star, Double(counts[star, default: 0]) / Double(reviews.count))
        })
    }
}

/// A page of reviews plus the server-side aggregate across all reviews.
public struct ReviewPage: Equatable, Sendable {
    public let stats: ReviewStats
    public let reviews: [Review]

    public init(stats: ReviewStats, reviews: [Review]) {
        self.stats = stats
        self.reviews = reviews
    }
}

public enum ReviewFilter: String, CaseIterable, Identifiable, Sendable {
    case all, withPhotos, verified

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .all: "All"
        case .withPhotos: "Photos"
        case .verified: "Verified"
        }
    }

    public func apply(to reviews: [Review]) -> [Review] {
        switch self {
        case .all: reviews
        case .withPhotos: reviews.filter { !$0.photoURLs.isEmpty }
        case .verified: reviews.filter(\.isVerified)
        }
    }
}
