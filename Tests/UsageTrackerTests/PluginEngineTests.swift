import Testing
@testable import UsageTracker

@Suite("PluginEngine Tests")
struct PluginEngineTests {

    @Test("Parse plugin metadata")
    func testParsePluginMetadata() throws {
        let js = """
        module.exports = {
            name: "TestPlugin",
            icon: "star",
            probe: async function() {
                return { label: "Test", current: 50, limit: 100 };
            }
        }
        """

        let engine = PluginEngine()
        let metadata = try engine.parseMetadata(from: js, id: "test")

        #expect(metadata.name == "TestPlugin")
        #expect(metadata.icon == "star")
    }

    @Test("Run probe returns single item")
    func testRunProbe() async throws {
        let js = """
        module.exports = {
            name: "Test",
            icon: "star",
            probe: async function() {
                return { label: "Usage", current: 75, limit: 100, resetLabel: "2h" };
            }
        }
        """

        let engine = PluginEngine()
        let items = try await engine.runProbe(js: js)

        #expect(items.count == 1)
        #expect(items[0].label == "Usage")
        #expect(items[0].current == 75)
        #expect(items[0].limit == 100)
        #expect(items[0].resetLabel == "2h")
    }

    @Test("Run probe returns array")
    func testRunProbeArray() async throws {
        let js = """
        module.exports = {
            name: "Test",
            icon: "star",
            probe: async function() {
                return [
                    { label: "A", current: 10, limit: 100 },
                    { label: "B", current: 20, limit: 50 }
                ];
            }
        }
        """

        let engine = PluginEngine()
        let items = try await engine.runProbe(js: js)

        #expect(items.count == 2)
        #expect(items[0].label == "A")
        #expect(items[1].label == "B")
        #expect(items[1].limit == 50)
    }
}
