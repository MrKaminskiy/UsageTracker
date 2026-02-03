import XCTest
@testable import UsageTracker

final class ModelsTests: XCTestCase {

    func testUsageItemPercentage() {
        let item = UsageItem(label: "Test", current: 25, limit: 100, resetLabel: nil)
        XCTAssertEqual(item.percentage, 25.0)
    }

    func testUsageItemPercentageZeroLimit() {
        let item = UsageItem(label: "Test", current: 10, limit: 0, resetLabel: nil)
        XCTAssertEqual(item.percentage, 0.0)
    }

    func testUsageItemColor() {
        let low = UsageItem(label: "Low", current: 30, limit: 100, resetLabel: nil)
        let mid = UsageItem(label: "Mid", current: 65, limit: 100, resetLabel: nil)
        let high = UsageItem(label: "High", current: 85, limit: 100, resetLabel: nil)

        XCTAssertEqual(low.color, .green)
        XCTAssertEqual(mid.color, .yellow)
        XCTAssertEqual(high.color, .red)
    }

    func testProviderMaxPercentage() {
        let provider = Provider(
            id: "test",
            name: "Test",
            icon: "star",
            items: [
                UsageItem(label: "A", current: 30, limit: 100, resetLabel: nil),
                UsageItem(label: "B", current: 80, limit: 100, resetLabel: nil)
            ],
            status: .loaded
        )
        XCTAssertEqual(provider.maxPercentage, 80.0)
    }

    func testProviderEmptyItems() {
        let provider = Provider(id: "test", name: "Test", icon: "star", items: [], status: .loaded)
        XCTAssertEqual(provider.maxPercentage, 0.0)
    }
}
