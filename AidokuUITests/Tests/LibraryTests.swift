import XCTest
import XCUIAutomation

final class LibraryTests: UITestBase {
    func testLibraryEmptyState() {
        LibraryScreen(app: app)
            .openLibraryTab()
            .assertLibraryEmptyState()
    }
}
