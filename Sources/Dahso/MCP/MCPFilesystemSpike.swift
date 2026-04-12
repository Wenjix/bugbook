import Foundation
import Darwin

struct MCPFilesystemSpikeReport {
    let protocolVersion: String
    let serverName: String
    let serverVersion: String
    let messageEncoding: MCPMessageEncoding
    let toolNames: [String]
    let calledToolName: String
    let toolCallResult: MCPToolCallResult

    var toolCallText: String {
        toolCallResult.content
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prettyPrintedSummary() -> String {
        let tools = toolNames.joined(separator: ", ")
        let body = toolCallText.isEmpty ? "<no text content>" : toolCallText
        return """
        MCP initialize OK
          protocol: \(protocolVersion)
          server: \(serverName) \(serverVersion)
          transport: \(messageEncoding == .contentLengthFramed ? "content-length" : "newline-delimited")
          tools: \(tools)
          called: \(calledToolName)
          result error flag: \(toolCallResult.isError == true ? "true" : "false")
          result:
        \(body)
        """
    }
}

enum MCPFilesystemSpike {
    private static let serverPackage = "@modelcontextprotocol/server-filesystem"

    static func run(testDirectoryURL: URL) async throws -> MCPFilesystemSpikeReport {
        do {
            return try await runOnce(testDirectoryURL: testDirectoryURL, messageEncoding: .contentLengthFramed)
        } catch let error as MCPClientError {
            guard shouldRetryWithLegacyEncoding(after: error) else {
                throw error
            }
            return try await runOnce(testDirectoryURL: testDirectoryURL, messageEncoding: .newlineDelimited)
        }
    }

    private static func runOnce(
        testDirectoryURL: URL,
        messageEncoding: MCPMessageEncoding
    ) async throws -> MCPFilesystemSpikeReport {
        let client = MCPStdioClient(
            command: "npx",
            arguments: ["-y", serverPackage, testDirectoryURL.path],
            messageEncoding: messageEncoding
        )

        do {
            try client.start()

            let initialize = try await client.initialize()
            let tools = try await client.listTools()
            let toolNames = tools.map(\.name)
            let toolCall = try await invokePreferredTool(
                with: client,
                toolNames: toolNames,
                testDirectoryURL: testDirectoryURL
            )

            await client.shutdown()

            return MCPFilesystemSpikeReport(
                protocolVersion: initialize.protocolVersion,
                serverName: initialize.serverInfo.name,
                serverVersion: initialize.serverInfo.version,
                messageEncoding: messageEncoding,
                toolNames: toolNames,
                calledToolName: toolCall.name,
                toolCallResult: toolCall.result
            )
        } catch {
            await client.shutdown()
            throw error
        }
    }

    private static func shouldRetryWithLegacyEncoding(after error: MCPClientError) -> Bool {
        switch error {
        case .invalidResponse, .responseEndedBeforeCompletion, .requestTimedOut:
            return true
        default:
            return false
        }
    }

    private static func invokePreferredTool(
        with client: MCPStdioClient,
        toolNames: [String],
        testDirectoryURL: URL
    ) async throws -> (name: String, result: MCPToolCallResult) {
        if toolNames.contains("list_directory") {
            struct Arguments: Encodable {
                let path: String
            }

            let resolvedPath = canonicalPath(for: testDirectoryURL)
            let result = try await client.callTool(
                name: "list_directory",
                arguments: Arguments(path: resolvedPath)
            )
            return ("list_directory", result)
        }

        if toolNames.contains("list_allowed_directories") {
            let result = try await client.callTool(name: "list_allowed_directories", arguments: EmptyObject())
            return ("list_allowed_directories", result)
        }

        throw MCPClientError.unsupportedToolCall(toolNames)
    }

    private static func canonicalPath(for url: URL) -> String {
        let bufferSize = Int(PATH_MAX)
        let resolvedBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { resolvedBuffer.deallocate() }

        return url.path.withCString { rawPath in
            guard realpath(rawPath, resolvedBuffer) != nil else {
                return url.path
            }
            return String(cString: resolvedBuffer)
        }
    }
}
