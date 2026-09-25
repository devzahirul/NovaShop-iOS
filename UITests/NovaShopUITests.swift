import XCTest

/// Critical-path UI tests only. Everything else is covered by fast unit tests on view models.
/// `-ui-testing` swaps in in-memory persistence and zero network latency for determinism.
final class NovaShopUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
    }

    @MainActor
    func testSignedInUserCanBuyAProductWithACoupon() {
        app.launchArguments.append("-signed-in")
        app.launch()

        let card = app.descendants(matching: .any)["product.card.amelie-floral-midi"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        XCTAssertTrue(app.staticTexts["product.title"].waitForExistence(timeout: 5))
        // Tapping Add without a size scrolls the (below-the-fold) size picker into view.
        app.buttons["product.addToCart"].tap()
        let sizeM = app.buttons["Size M"]
        XCTAssertTrue(sizeM.waitForExistence(timeout: 2))
        sizeM.tap()
        app.buttons["product.addToCart"].tap()

        app.buttons["toolbar.cart"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Amelie Floral Midi Dress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Taupe Floral / M"].exists, "Selected colour and size are carried into the cart")

        app.buttons["cart.coupon"].tap()
        let field = app.textFields["coupon.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("SUMMER20")
        app.buttons["coupon.apply"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["coupon.success"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["cart.checkout"].tap()
        let continueButton = app.buttons["checkout.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap() // shipping → payment
        continueButton.tap() // payment → review
        app.buttons["checkout.placeOrder"].tap()

        XCTAssertTrue(app.staticTexts["confirmation.orderNumber"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testGuestIsAskedToSignInAtCheckoutAndResumes() {
        app.launch()

        let card = app.descendants(matching: .any)["product.card.elise-sunglasses"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        // One-size product: no size selection required.
        app.buttons["product.addToCart"].tap()
        app.buttons["toolbar.cart"].firstMatch.tap()
        app.buttons["cart.checkout"].tap()

        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "Guest checkout should present sign in")
        email.tap()
        email.typeText("reviewer@novashop.example")
        let password = app.secureTextFields["auth.password"]
        password.tap()
        password.typeText("password123")
        app.buttons["auth.signIn"].tap()

        XCTAssertTrue(app.buttons["checkout.continue"].waitForExistence(timeout: 10), "Should resume into checkout after sign in")
    }

    @MainActor
    func testWishlistToggleUpdatesWishlistTab() {
        app.launch()
        let heart = app.buttons["wishlist.toggle.amelie-floral-midi"].firstMatch
        XCTAssertTrue(heart.waitForExistence(timeout: 10))
        heart.tap()

        app.tabBars.buttons["Wishlist"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["product.card.amelie-floral-midi"].waitForExistence(timeout: 5))
    }

    /// Cold-launch regression guard. Run on a real device for meaningful numbers; CI tracks the trend.
    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
