// swift-tools-version: 6.0
//
// NovaKit — every line of product code lives here. The app target is a ~20 line shell.
//
// Layering (arrows = "depends on"; nothing points upward):
//
//   AppFeature ─► *Feature ─► ProductUI ─► DesignSystem ─► ImagePipeline ─► NovaCore
//        │             └────► Routing ───► Domain ────────────────────────► NovaCore
//        └──► Data ─► Networking ─► NovaCore
//
// Features never import each other or `Data`. They talk through `Domain` protocols and
// `Routing` values, so any feature can be built, previewed and tested in isolation.

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

extension Target {
    static func module(
        _ name: String,
        dependencies: [Target.Dependency] = [],
        resources: [Resource]? = nil
    ) -> Target {
        .target(name: name, dependencies: dependencies, resources: resources, swiftSettings: strictSettings)
    }

    static func feature(_ name: String, extra: [Target.Dependency] = []) -> Target {
        .module(name, dependencies: ["NovaCore", "Domain", "DesignSystem", "ProductUI", "Routing"] + extra)
    }

    static func tests(_ name: String, dependencies: [Target.Dependency]) -> Target {
        .testTarget(name: name, dependencies: dependencies + ["TestSupport"], swiftSettings: strictSettings)
    }
}

let package = Package(
    name: "NovaKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    targets: [
        // MARK: Foundation layers

        .module("NovaCore"),
        .module("Domain", dependencies: ["NovaCore"]),
        .module("Networking", dependencies: ["NovaCore"]),
        .module("Data", dependencies: ["Domain", "Networking", "NovaCore"], resources: [.process("Fixtures")]),
        .module("ImagePipeline", dependencies: ["NovaCore"]),
        .module("DesignSystem", dependencies: ["ImagePipeline", "NovaCore"]),
        .module("ProductUI", dependencies: ["Domain", "DesignSystem", "Routing"]),
        .module("Routing", dependencies: ["Domain", "NovaCore"]),

        // MARK: Features

        .feature("AuthFeature"),
        .feature("HomeFeature"),
        .feature("CatalogFeature"),
        .feature("ProductFeature"),
        .feature("WishlistFeature"),
        .feature("CartFeature"),
        .feature("CheckoutFeature"),
        .feature("AccountFeature"),

        // MARK: Composition root

        .module("AppFeature", dependencies: [
            "NovaCore", "Domain", "Data", "Networking", "ImagePipeline", "DesignSystem", "Routing",
            "AuthFeature", "HomeFeature", "CatalogFeature", "ProductFeature",
            "WishlistFeature", "CartFeature", "CheckoutFeature", "AccountFeature",
        ]),

        // MARK: Test support (fakes, fixtures, immediate clock) — linked by tests only

        .module("TestSupport", dependencies: ["Domain", "NovaCore"]),

        // MARK: Tests

        .tests("DomainTests", dependencies: ["Domain"]),
        .tests("NetworkingTests", dependencies: ["Networking"]),
        .tests("DataTests", dependencies: ["Data", "Domain", "Networking"]),
        .tests("ImagePipelineTests", dependencies: ["ImagePipeline"]),
        .tests("RoutingTests", dependencies: ["Routing", "Domain"]),
        .tests("FeatureTests", dependencies: [
            "Domain", "AuthFeature", "CatalogFeature", "ProductFeature", "CartFeature", "CheckoutFeature", "HomeFeature",
        ]),
    ]
)
