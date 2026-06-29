//
//  Party_WatcherUITests.swift
//  Party WatcherUITests
//
//  End-to-end UI flows over the real app, driven through the accessibility
//  identifiers the views expose. These exercise the journeys that unit tests
//  can't reach — launch, the chat input clearing after send (bug #5), adding a
//  contact through the sheet, marking safe, and opening Settings.
//
//  Kept out of the gating CI job (which runs only "Party WatcherTests") so the
//  fast unit signal stays fast; run locally or in an optional UI job.
//

import XCTest

final class Party_WatcherUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTitleAndStatusHero() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["SafeWalk"].waitForExistence(timeout: 5))
        // The status hero announces the current safety state.
        XCTAssertTrue(app.staticTexts["You're safe"].exists)
    }

    @MainActor
    func testSendingMessageClearsTheInput() throws {
        let app = XCUIApplication()
        app.launch()

        let input = app.textFields["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("hello there")

        app.buttons["sendButton"].tap()

        // Bug #5 regression: after sending, the field is cleared (and the
        // keyboard dismissed). The placeholder returns when the value is empty.
        XCTAssertEqual(input.value as? String, "Type your reply…")
    }

    @MainActor
    func testAddingContactShowsItInTheList() throws {
        let app = XCUIApplication()
        app.launch()

        // Scroll the contacts card into view and open the add sheet.
        let addButton = app.buttons["addContactButton"]
        if !addButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let name = app.textFields["contactNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Alex Roommate")

        let phone = app.textFields["contactPhoneField"]
        phone.tap(); phone.typeText("5125550100")

        app.buttons["confirmAddContactButton"].tap()

        XCTAssertTrue(app.staticTexts["Alex Roommate"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMarkSafeKeepsStatusSafe() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["imSafeButton"].tap()
        XCTAssertTrue(app.staticTexts["You're safe"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOpeningSettingsShowsTheForm() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        // Dismiss to confirm the Cancel control is wired.
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["SafeWalk"].waitForExistence(timeout: 5))
    }
}
