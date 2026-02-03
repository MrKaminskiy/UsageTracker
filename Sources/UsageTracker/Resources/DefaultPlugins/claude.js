// Claude Pro usage tracker
// Note: This is a demo plugin showing the expected format.
// Real implementation would need to fetch from claude.ai with auth.

module.exports = {
    name: "Claude",
    icon: "brain",

    async probe() {
        // TODO: Implement actual fetching from claude.ai
        // This would require:
        // 1. Reading session cookie from browser
        // 2. Making authenticated request to usage API
        // 3. Parsing the response

        // For now, return demo data to show the UI works
        return [
            {
                label: "Session",
                current: 15,
                limit: 100,
                resetLabel: "4h 30m"
            },
            {
                label: "All models",
                current: 42,
                limit: 100,
                resetLabel: "18h 15m"
            },
            {
                label: "Weekly",
                current: 23,
                limit: 100,
                resetLabel: "Wed 2PM"
            }
        ];
    }
};
