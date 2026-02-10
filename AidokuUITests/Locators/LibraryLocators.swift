import XCUIAutomation

enum LibraryLocators {
    static var libraryTabButton: XCUIElement {
        XCUIApplication().tabBars.buttons["Library"]
    }
}
