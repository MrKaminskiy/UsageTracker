import Foundation
import Network

actor ExtensionServer {
    private var listener: NWListener?
    private let port: UInt16 = 19284
    private var receivedData: [String: ExtensionData] = [:]

    struct ExtensionData: Codable {
        let providerId: String
        let items: [ExtensionUsageItem]
        let timestamp: Double

        struct ExtensionUsageItem: Codable {
            let label: String
            let current: Double
            let limit: Double
            let resetLabel: String?
        }
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func getData(for providerId: String) -> ExtensionData? {
        let data = receivedData[providerId]
        // Only return if less than 5 minutes old
        if let data = data, Date().timeIntervalSince1970 - data.timestamp < 300 {
            return data
        }
        return nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let data = data, error == nil else {
                connection.cancel()
                return
            }

            Task {
                await self?.processRequest(data: data, connection: connection)
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        // Parse HTTP request to extract JSON body
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: "Invalid request")
            return
        }

        // Handle OPTIONS preflight
        if requestString.hasPrefix("OPTIONS") {
            sendResponse(connection: connection, status: 200, body: "")
            return
        }

        // Find JSON body after headers
        if let bodyStart = requestString.range(of: "\r\n\r\n") {
            let bodyString = String(requestString[bodyStart.upperBound...])
            if let bodyData = bodyString.data(using: .utf8),
               let extensionData = try? JSONDecoder().decode(ExtensionData.self, from: bodyData) {
                receivedData[extensionData.providerId] = extensionData
                sendResponse(connection: connection, status: 200, body: "{\"ok\":true}")
                return
            }
        }

        sendResponse(connection: connection, status: 400, body: "{\"error\":\"Invalid JSON\"}")
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText = status == 200 ? "OK" : "Bad Request"
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
