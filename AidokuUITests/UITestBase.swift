import XCTest
import XCUIAutomation

class UITestBase: XCTestCase {
    // MARK: - Shared instance (reusable across tests)

    public lazy var app = XCUIApplication()

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        try super.setUpWithError()

        app.launchArguments += ["UI-Testing"]
        app.launchEnvironment["RESET_STATE"] = "true"
        app.launch()

        XCTAssertTrue(LibraryLocators.libraryTabButton.waitForExistence(timeout: 10),
                      "App did not launch to main screen in time")
    }

    override func tearDownWithError() throws {
        app.terminate()

        try super.tearDownWithError()
    }

    // ── Automatic screenshot on ANY assertion failure ──
    override func record(_ issue: XCTIssue) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Failure Screenshot - \(invocation?.selector.description ?? "unknown")"
        attachment.lifetime = .keepAlways
        add(attachment)

        let hierarchy = app.debugDescription
        let textAttachment = XCTAttachment(string: hierarchy)
        textAttachment.name = "App Hierarchy at Failure"
        textAttachment.lifetime = .keepAlways
        add(textAttachment)

        super.record(issue)
    }
}
