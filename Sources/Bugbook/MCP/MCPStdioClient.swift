import Foundation
import Darwin

enum MCPClientError: LocalizedError {
    case processNotRunning
    case invalidResponse(String)
    case requestFailed(code: Int, message: String)
    case unsupportedToolCall([String])
    case responseEndedBeforeCompletion(Int)
    case requestTimedOut(method: String, seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .processNotRunning:
            return "The MCP server process is not running."
        case let .invalidResponse(message):
            return "Invalid MCP response: \(message)"
        case let .requestFailed(code, message):
            return "MCP request failed (\(code)): \(message)"
        case let .unsupportedToolCall(toolNames):
            return "No supported spike tool found. Available tools: \(toolNames.joined(separator: ", "))"
        case let .responseEndedBeforeCompletion(id):
            return "The MCP server closed stdout before completing request \(id)."
        case let .requestTimedOut(method, seconds):
            return "Timed out waiting for MCP response to \(method) after \(Int(seconds))s."
        }
    }
}

struct MCPImplementationInfo: Codable {
    let name: String
    let version: String
}

struct MCPInitializeResult: Decodable {
    let protocolVersion: String
    let serverInfo: MCPImplementationInfo
    let instructions: String?
}

struct MCPTool: Decodable {
    let name: String
    let description: String?
}

struct MCPToolCallResult: Decodable {
    let content: [MCPToolContent]
    let isError: Bool?
}

struct MCPToolContent: Decodable {
    let type: String
    let text: String?
}

private struct MCPInitializeParams: Encodable {
    let protocolVersion: String
    let capabilities: EmptyObject
    let clientInfo: MCPImplementationInfo
}

private struct MCPRequestEnvelope<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: Params
}

private struct MCPNotificationEnvelope<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: Params?
}

private struct MCPNotificationWithoutParamsEnvelope: Encodable {
    let jsonrpc = "2.0"
    let method: String
}

private struct MCPToolCallParams<Arguments: Encodable>: Encodable {
    let name: String
    let arguments: Arguments
}

struct EmptyObject: Codable {}

enum MCPMessageEncoding {
    case newlineDelimited
    case contentLengthFramed
}

final class MCPStdioClient {
    private let command: String
    private let arguments: [String]
    private let currentDirectoryURL: URL?
    private let requestTimeout: TimeInterval
    private let messageEncoding: MCPMessageEncoding

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private var stdoutMessages: AsyncThrowingStream<Data, Error>.Iterator?
    private var stdoutReaderTask: Task<Void, Never>?
    private var stderrReaderTask: Task<Void, Never>?
    private var nextRequestID = 1

    init(
        command: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        requestTimeout: TimeInterval = 30,
        messageEncoding: MCPMessageEncoding = .contentLengthFramed
    ) {
        self.command = command
        self.arguments = arguments
        self.currentDirectoryURL = currentDirectoryURL
        self.requestTimeout = requestTimeout
        self.messageEncoding = messageEncoding
    }

    func start() throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let (stdoutStream, stdoutTask) = Self.makeMessageStream(from: stdoutPipe.fileHandleForReading)
        stdoutMessages = stdoutStream.makeAsyncIterator()
        stdoutReaderTask = stdoutTask

        stderrReaderTask = Task {
            do {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    guard !line.isEmpty else { continue }
                    print("[MCP stderr] \(line)")
                }
            } catch {
                print("[MCP stderr] reader failed: \(error.localizedDescription)")
            }
        }
    }

    func initialize(
        protocolVersion: String = "2025-11-25",
        clientInfo: MCPImplementationInfo = MCPImplementationInfo(name: "BugbookMCPSpike", version: "0.1.0")
    ) async throws -> MCPInitializeResult {
        let params = MCPInitializeParams(
            protocolVersion: protocolVersion,
            capabilities: EmptyObject(),
            clientInfo: clientInfo
        )
        let result: MCPInitializeResult = try await sendRequest(method: "initialize", params: params)
        try sendNotification(method: "notifications/initialized", params: Optional<EmptyObject>.none)
        return result
    }

    func listTools() async throws -> [MCPTool] {
        struct Result: Decodable {
            let tools: [MCPTool]
        }
        let result: Result = try await sendRequest(method: "tools/list", params: EmptyObject())
        return result.tools
    }

    func callTool<Arguments: Encodable>(name: String, arguments: Arguments) async throws -> MCPToolCallResult {
        let params = MCPToolCallParams(name: name, arguments: arguments)
        return try await sendRequest(method: "tools/call", params: params)
    }

    func shutdown() async {
        stdinPipe.fileHandleForWriting.closeFile()

        if process.isRunning {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if process.isRunning {
            process.terminate()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }

        stdoutReaderTask?.cancel()
        stderrReaderTask?.cancel()
    }

    private func sendNotification<Params: Encodable>(method: String, params: Params?) throws {
        guard process.isRunning else {
            throw MCPClientError.processNotRunning
        }

        let data: Data
        if let params {
            let envelope = MCPNotificationEnvelope(method: method, params: params)
            data = try JSONEncoder().encode(envelope)
        } else {
            let envelope = MCPNotificationWithoutParamsEnvelope(method: method)
            data = try JSONEncoder().encode(envelope)
        }
        try writeFramedMessage(data)
    }

    private func sendRequest<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params,
        as resultType: Result.Type = Result.self
    ) async throws -> Result {
        guard process.isRunning else {
            throw MCPClientError.processNotRunning
        }

        let requestID = nextRequestID
        nextRequestID += 1

        let envelope = MCPRequestEnvelope(id: requestID, method: method, params: params)
        let data = try JSONEncoder().encode(envelope)
        try writeFramedMessage(data)

        let responseTask = Task {
            try await self.readResponse(matching: requestID, as: resultType)
        }

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(requestTimeout * 1_000_000_000))
            responseTask.cancel()
        }

        defer { timeoutTask.cancel() }

        do {
            return try await responseTask.value
        } catch is CancellationError {
            throw MCPClientError.requestTimedOut(method: method, seconds: requestTimeout)
        }
    }

    private func readResponse<Result: Decodable>(
        matching requestID: Int,
        as resultType: Result.Type
    ) async throws -> Result {
        guard var messages = stdoutMessages else {
            throw MCPClientError.processNotRunning
        }

        defer { stdoutMessages = messages }

        while let responseData = try await messages.next() {
            guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                let payload = String(data: responseData, encoding: .utf8) ?? "<non-utf8>"
                throw MCPClientError.invalidResponse(payload)
            }

            if object["method"] != nil, object["id"] == nil {
                continue
            }

            guard let idValue = object["id"] else {
                let payload = String(data: responseData, encoding: .utf8) ?? "<non-utf8>"
                throw MCPClientError.invalidResponse(payload)
            }

            let responseID: Int?
            if let intID = idValue as? Int {
                responseID = intID
            } else if let numberID = idValue as? NSNumber {
                responseID = numberID.intValue
            } else if let stringID = idValue as? String {
                responseID = Int(stringID)
            } else {
                responseID = nil
            }

            guard responseID == requestID else {
                continue
            }

            if let errorObject = object["error"] as? [String: Any] {
                let code = (errorObject["code"] as? NSNumber)?.intValue ?? -1
                let message = (errorObject["message"] as? String) ?? "Unknown error"
                throw MCPClientError.requestFailed(code: code, message: message)
            }

            guard let resultObject = object["result"] else {
                let payload = String(data: responseData, encoding: .utf8) ?? "<non-utf8>"
                throw MCPClientError.invalidResponse(payload)
            }

            let resultData = try JSONSerialization.data(withJSONObject: resultObject)
            return try JSONDecoder().decode(resultType, from: resultData)
        }

        throw MCPClientError.responseEndedBeforeCompletion(requestID)
    }

    private func writeFramedMessage(_ data: Data) throws {
        guard process.isRunning else {
            throw MCPClientError.processNotRunning
        }

        switch messageEncoding {
        case .contentLengthFramed:
            let header = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
            stdinPipe.fileHandleForWriting.write(header)
            stdinPipe.fileHandleForWriting.write(data)
        case .newlineDelimited:
            stdinPipe.fileHandleForWriting.write(data)
            stdinPipe.fileHandleForWriting.write(Data([0x0A]))
        }
    }

    private static func makeMessageStream(
        from fileHandle: FileHandle
    ) -> (AsyncThrowingStream<Data, Error>, Task<Void, Never>) {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        let stream = AsyncThrowingStream<Data, Error> { continuation = $0 }
        let task = Task {
            var buffer = Data()

            while !Task.isCancelled {
                let chunk = fileHandle.availableData
                if chunk.isEmpty {
                    if !buffer.isEmpty {
                        continuation.finish(throwing: MCPClientError.invalidResponse("Unexpected EOF while reading framed MCP message."))
                    } else {
                        continuation.finish()
                    }
                    return
                }

                buffer.append(chunk)

                do {
                    while let message = try extractNextMessage(from: &buffer) {
                        continuation.yield(message)
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
            }

            continuation.finish()
        }
        return (stream, task)
    }

    private static func extractNextMessage(from buffer: inout Data) throws -> Data? {
        if let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            let trimmedLine = lineData.last == 0x0D ? lineData.dropLast() : lineData[...]
            if !trimmedLine.isEmpty,
               let firstByte = trimmedLine.first,
               firstByte == 0x7B || firstByte == 0x5B {
                let message = Data(trimmedLine)
                buffer.removeSubrange(...newlineIndex)
                return message
            }
        }

        let separator = Data("\r\n\r\n".utf8)
        let fallbackSeparator = Data("\n\n".utf8)

        let headerRange: Range<Data.Index>
        if let range = buffer.range(of: separator) {
            headerRange = range
        } else if let range = buffer.range(of: fallbackSeparator) {
            headerRange = range
        } else {
            return nil
        }

        let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw MCPClientError.invalidResponse("MCP header is not valid UTF-8.")
        }

        let headerLines = headerText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard let contentLengthLine = headerLines.first(where: { $0.lowercased().hasPrefix("content-length:") }) else {
            throw MCPClientError.invalidResponse("Missing Content-Length header.")
        }

        let rawLength = contentLengthLine.dropFirst("Content-Length:".count).trimmingCharacters(in: .whitespaces)
        guard let contentLength = Int(rawLength), contentLength >= 0 else {
            throw MCPClientError.invalidResponse("Invalid Content-Length header: \(contentLengthLine)")
        }

        let bodyStart = headerRange.upperBound
        guard buffer.count >= bodyStart + contentLength else {
            return nil
        }

        let message = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        buffer.removeSubrange(0..<(bodyStart + contentLength))
        return message
    }
}
