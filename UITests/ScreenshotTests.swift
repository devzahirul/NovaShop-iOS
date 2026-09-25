import XCTest

/// Automated screenshot capture (the same approach fastlane `snapshot` uses for App Store assets).
/// Run: `make screenshots` — images are exported from the .xcresult into `docs/screenshots`.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testCaptureLightMode() {
        capture(appearance: "light")
    }

    @MainActor
    func testCaptureDarkMode() {
        capture(appearance: "dark", screens: ["home", "product", "cart"])
    }

    @MainActor
    private func capture(appearance: String, screens: Set<String>? = nil) {
        let app = XCUIApplication()
        // `-key value` launch arguments land in the UserDefaults argument domain → @AppStorage.
        app.launchArguments = ["-ui-testing", "-signed-in", "-settings.appearance", appearance]
        app.launch()

        func shot(_ name: String) {
            guard screens?.contains(name) ?? true else { return }
            sleep(2) // let remote images settle — screenshots only, never in functional tests
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "\(appearance)-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        XCTAssertTrue(app.descendants(matching: .any)["product.card.amelie-floral-midi"].waitForExistence(timeout: 15))
        shot("home")

        // Category + filter sheet
        app.tabBars.buttons["Shop"].tap()
        app.buttons["shop.category.dresses"].firstMatch.tap()
        _ = app.buttons["listing.filter"].waitForExistence(timeout: 5)
        shot("category")
        if screens == nil {
            app.buttons["listing.filter"].tap()
            shot("filter")
            app.buttons["Close"].tap()
        }

        // Product detail
        app.tabBars.buttons["Home"].tap()
        app.descendants(matching: .any)["product.card.amelie-floral-midi"].firstMatch.tap()
        _ = app.staticTexts["product.title"].waitForExistence(timeout: 5)
        shot("product")

        app.buttons["product.addToCart"].tap()
        app.buttons["Size M"].tap()
        app.buttons["product.addToCart"].tap()
        app.buttons["toolbar.cart"].firstMatch.tap()
        app.buttons["cart.coupon"].tap()
        app.textFields["coupon.field"].tap()
        app.textFields["coupon.field"].typeText("SUMMER20")
        app.buttons["coupon.apply"].tap()
        _ = app.descendants(matching: .any)["coupon.success"].waitForExistence(timeout: 5)
        shot("coupon")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        shot("cart")

        guard screens == nil else { return }
        app.buttons["cart.checkout"].tap()
        _ = app.buttons["checkout.continue"].waitForExistence(timeout: 5)
        shot("checkout")
        app.buttons["checkout.continue"].tap()
        app.buttons["checkout.continue"].tap()
        shot("review")
        app.buttons["checkout.placeOrder"].tap()
        _ = app.staticTexts["confirmation.orderNumber"].waitForExistence(timeout: 10)
        shot("confirmation")

        app.tabBars.buttons["Search"].tap()
        shot("search")
        app.tabBars.buttons["Account"].tap()
        shot("account")
    }
}
