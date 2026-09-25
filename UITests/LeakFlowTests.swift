import XCTest

/// Drives the purchase flow in an app that is *already running* — launched by Instruments.
///
/// Why: on a physical device the Leaks instrument can't attach to a running process (its memory
/// scanner must hook libmalloc at launch), so Instruments has to launch the app and this test only
/// steers it. In a normal test run nothing is running yet, so the test skips itself.
///
///     make leak-check   # Instruments launches the app, this test drives it, leaks are reported
final class LeakFlowTests: XCTestCase {
    @MainActor
    func testDrivePurchaseFlowInRunningApp() throws {
        let app = XCUIApplication()
        guard app.state == .runningForeground || app.state == .runningBackground else {
            throw XCTSkip("Only used by `make leak-check` (Instruments launches the app first).")
        }
        app.activate()

        // Browse → product (twice, to exercise push/pop) → bag → coupon → checkout → confirmation.
        for _ in 0 ..< 2 {
            let card = app.descendants(matching: .any)["product.card.amelie-floral-midi"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 15))
            card.tap()
            XCTAssertTrue(app.staticTexts["product.title"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        app.descendants(matching: .any)["product.card.amelie-floral-midi"].firstMatch.tap()
        app.buttons["product.addToCart"].tap() // scrolls to sizes
        app.buttons["Size M"].tap()
        app.buttons["product.addToCart"].tap()
        app.buttons["toolbar.cart"].firstMatch.tap()

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
        continueButton.tap()
        continueButton.tap()
        app.buttons["checkout.placeOrder"].tap()
        XCTAssertTrue(app.staticTexts["confirmation.orderNumber"].waitForExistence(timeout: 15))

        // Leave the flow's screens so their view models *should* be freed before the leak scan.
        app.buttons["confirmation.continue"].tap()
        app.tabBars.buttons["Wishlist"].tap()
        app.tabBars.buttons["Home"].tap()
        sleep(3) // screenshot-style settle time: let the final leak snapshot see the idle app
    }
}
