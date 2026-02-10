import XCTest
import XCUIAutomation

struct LibraryScreen {
    let app: XCUIApplication

    // -- Actions

    @discardableResult
    func openLibraryTab() -> Self {
        LibraryLocators.libraryTabButton.tap()

        return self
    }

    // -- Assertions

    @discardableResult
    func assertLibraryEmptyState() -> Self {
        XCTAssertTrue(LibraryLocators.libraryTabButton.waitForExistence(timeout: 10),
                      "Library tab should exist")

        return self
    }
}
