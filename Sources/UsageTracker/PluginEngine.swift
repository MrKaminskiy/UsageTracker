import Foundation
@preconcurrency import JavaScriptCore

struct PluginMetadata {
    let id: String
    let name: String
    let icon: String
}

enum PluginError: Error, LocalizedError {
    case invalidPlugin(String)
    case probeTimeout
    case probeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlugin(let reason): return "Invalid plugin: \(reason)"
        case .probeTimeout: return "Plugin timed out"
        case .probeFailed(let reason): return "Probe failed: \(reason)"
        }
    }
}

private final class CompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasCompleted = false

    func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasCompleted {
            return false
        }
        hasCompleted = true
        return true
    }
}

final class PluginEngine: @unchecked Sendable {
    private let timeout: TimeInterval = 10.0

    func parseMetadata(from js: String, id: String) throws -> PluginMetadata {
        let context = JSContext()!
        setupContext(context)

        let wrappedJS = """
        var module = { exports: {} };
        \(js)
        module.exports;
        """

        guard let result = context.evaluateScript(wrappedJS),
              !result.isUndefined else {
            throw PluginError.invalidPlugin("Could not evaluate plugin")
        }

        guard let name = result.objectForKeyedSubscript("name")?.toString(),
              !name.isEmpty && name != "undefined" else {
            throw PluginError.invalidPlugin("Missing 'name' property")
        }

        let icon = result.objectForKeyedSubscript("icon")?.toString() ?? "questionmark.circle"

        return PluginMetadata(id: id, name: name, icon: icon)
    }

    func runProbe(js: String) async throws -> [UsageItem] {
        let completionState = CompletionState()

        return try await withCheckedThrowingContinuation { continuation in
            let context = JSContext()!
            setupContext(context)

            let resolve: @convention(block) (JSValue) -> Void = { result in
                guard completionState.tryComplete() else { return }
                let items = self.parseProbeResult(result)
                continuation.resume(returning: items)
            }

            let reject: @convention(block) (JSValue) -> Void = { error in
                guard completionState.tryComplete() else { return }
                let message = error.toString() ?? "Unknown error"
                continuation.resume(throwing: PluginError.probeFailed(message))
            }

            context.setObject(resolve, forKeyedSubscript: "__resolve" as NSString)
            context.setObject(reject, forKeyedSubscript: "__reject" as NSString)

            let wrappedJS = """
            var module = { exports: {} };
            \(js)

            (async function() {
                try {
                    const result = await module.exports.probe();
                    __resolve(result);
                } catch (e) {
                    __reject(e.toString());
                }
            })();
            """

            context.evaluateScript(wrappedJS)

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard completionState.tryComplete() else { return }
                continuation.resume(throwing: PluginError.probeTimeout)
            }
        }
    }

    private func setupContext(_ context: JSContext) {
        let log: @convention(block) (String) -> Void = { message in
            print("[Plugin] \(message)")
        }
        context.setObject(log, forKeyedSubscript: "log" as NSString)

        context.evaluateScript("""
            var console = {
                log: function(...args) { log(args.join(' ')); },
                error: function(...args) { log('ERROR: ' + args.join(' ')); },
                warn: function(...args) { log('WARN: ' + args.join(' ')); }
            };
        """)

        context.exceptionHandler = { _, exception in
            print("[Plugin Error] \(exception?.toString() ?? "Unknown")")
        }

        // Add fetch function using URLSession with completion handler to avoid Swift 6 concurrency issues
        let fetchBlock: @convention(block) (String, JSValue?) -> JSValue? = { urlString, options in
            let promiseJS = """
            new Promise(function(resolve, reject) {
                __pendingFetch = { resolve: resolve, reject: reject };
            })
            """
            let promise = context.evaluateScript(promiseJS)

            guard let url = URL(string: urlString) else {
                context.evaluateScript("__pendingFetch.reject(new Error('Invalid URL'))")
                return promise
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 10

            // Extract options synchronously
            if let opts = options, !opts.isUndefined {
                if let m = opts.objectForKeyedSubscript("method")?.toString(), m != "undefined" {
                    request.httpMethod = m
                }
                if let h = opts.objectForKeyedSubscript("headers"), h.isObject {
                    let keys = context.evaluateScript("Object.keys")?.call(withArguments: [h])
                    let length = keys?.objectForKeyedSubscript("length")?.toInt32() ?? 0
                    for i in 0..<length {
                        if let key = keys?.objectAtIndexedSubscript(Int(i))?.toString(),
                           let value = h.objectForKeyedSubscript(key)?.toString() {
                            request.setValue(value, forHTTPHeaderField: key)
                        }
                    }
                }
                if let b = opts.objectForKeyedSubscript("body")?.toString(), b != "undefined" {
                    request.httpBody = b.data(using: .utf8)
                }
            }

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let errorMessage = error.localizedDescription.replacingOccurrences(of: "'", with: "\\'")
                        context.evaluateScript("__pendingFetch.reject(new Error('\(errorMessage)'))")
                        return
                    }

                    guard let data = data, let text = String(data: data, encoding: .utf8) else {
                        context.evaluateScript("__pendingFetch.reject(new Error('No data'))")
                        return
                    }

                    let httpResponse = response as? HTTPURLResponse
                    let status = httpResponse?.statusCode ?? 200

                    let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "`", with: "\\`")
                        .replacingOccurrences(of: "$", with: "\\$")

                    context.evaluateScript("""
                        __pendingFetch.resolve({
                            ok: \(status >= 200 && status < 300),
                            status: \(status),
                            text: function() { return Promise.resolve(`\(escaped)`); },
                            json: function() { return Promise.resolve(JSON.parse(`\(escaped)`)); }
                        })
                    """)
                }
            }
            task.resume()

            return promise
        }
        context.setObject(fetchBlock, forKeyedSubscript: "fetch" as NSString)

        // Add readFile function
        let readFileBlock: @convention(block) (String) -> JSValue? = { path in
            let promiseJS = """
            new Promise(function(resolve, reject) {
                __pendingRead = { resolve: resolve, reject: reject };
            })
            """
            let promise = context.evaluateScript(promiseJS)

            DispatchQueue.global(qos: .userInitiated).async {
                let expandedPath = NSString(string: path).expandingTildeInPath

                do {
                    let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
                    let escaped = content.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "`", with: "\\`")
                        .replacingOccurrences(of: "$", with: "\\$")

                    DispatchQueue.main.async {
                        context.evaluateScript("__pendingRead.resolve(`\(escaped)`)")
                    }
                } catch {
                    let errorMessage = error.localizedDescription.replacingOccurrences(of: "'", with: "\\'")
                    DispatchQueue.main.async {
                        context.evaluateScript("__pendingRead.reject(new Error('\(errorMessage)'))")
                    }
                }
            }

            return promise
        }
        context.setObject(readFileBlock, forKeyedSubscript: "readFile" as NSString)

        // Add env function
        let envBlock: @convention(block) (String) -> String? = { name in
            ProcessInfo.processInfo.environment[name]
        }
        context.setObject(envBlock, forKeyedSubscript: "env" as NSString)
    }

    private func parseProbeResult(_ result: JSValue) -> [UsageItem] {
        var items: [UsageItem] = []

        if result.isArray {
            let length = result.objectForKeyedSubscript("length")?.toInt32() ?? 0
            for i in 0..<length {
                if let item = result.objectAtIndexedSubscript(Int(i)),
                   let parsed = parseUsageItem(item) {
                    items.append(parsed)
                }
            }
        } else if let parsed = parseUsageItem(result) {
            items.append(parsed)
        }

        return items
    }

    private func parseUsageItem(_ value: JSValue) -> UsageItem? {
        guard let label = value.objectForKeyedSubscript("label")?.toString(),
              !label.isEmpty && label != "undefined" else {
            return nil
        }

        let current = value.objectForKeyedSubscript("current")?.toDouble() ?? 0
        let limit = value.objectForKeyedSubscript("limit")?.toDouble() ?? 100

        let resetLabelValue = value.objectForKeyedSubscript("resetLabel")
        let resetLabel: String? = (resetLabelValue?.isString == true) ? resetLabelValue?.toString() : nil

        return UsageItem(label: label, current: current, limit: limit, resetLabel: resetLabel)
    }
}
