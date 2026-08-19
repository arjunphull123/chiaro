import Foundation
import Network
import AppKit
import CoreImage

/// Local MCP server (ADR 0008): while Chiaro runs, coding agents can list photos,
/// read and set EditStates, open the editor, fetch previews, and export — the same
/// EditState contract every UI input uses (ADR 0003). Streamable HTTP transport at
/// http://127.0.0.1:<port>/mcp, discovery file at ~/.chiaro/mcp.json.
final class MCPServer {
    static let shared = MCPServer()
    static let preferredPort: UInt16 = 24242

    private var listener: NWListener?
    private(set) nonisolated(unsafe) var port: UInt16 = 0
    @MainActor weak var library: Library?

    @MainActor
    func start(library: Library) {
        self.library = library
        for candidate in [Self.preferredPort, 0] {
            guard let l = try? NWListener(
                using: .tcp,
                on: NWEndpoint.Port(rawValue: candidate) ?? .any
            ) else { continue }
            listener = l
            break
        }
        guard let listener else { return }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.receive(on: connection, buffer: Data())
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let self {
                self.port = self.listener?.port?.rawValue ?? 0
                self.writeDiscoveryFile()
            }
        }
        listener.start(queue: .global())
    }

    func stop() {
        listener?.cancel()
        try? FileManager.default.removeItem(at: Self.discoveryURL)
    }

    static let discoveryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".chiaro/mcp.json")

    private func writeDiscoveryFile() {
        let info: [String: Any] = [
            "app": "Chiaro",
            "version": "0.1",
            "transport": "http",
            "url": "http://127.0.0.1:\(port)/mcp",
            "pid": ProcessInfo.processInfo.processIdentifier,
        ]
        try? FileManager.default.createDirectory(
            at: Self.discoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted) {
            try? data.write(to: Self.discoveryURL)
        }
    }

    // MARK: - Minimal HTTP

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self, error == nil else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parseRequest(buffer) {
                self.handle(body: request) { response in
                    let payload = response ?? Data()
                    let status = response == nil ? "202 Accepted" : "200 OK"
                    var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n"
                    head += "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
                    connection.send(
                        content: Data(head.utf8) + payload,
                        completion: .contentProcessed { _ in connection.cancel() }
                    )
                }
            } else if done {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    /// Returns the body once the full request (headers + Content-Length bytes) has arrived.
    private static func parseRequest(_ data: Data) -> Data? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        let length = head.split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        let body = data[headerEnd.upperBound...]
        return body.count >= length ? Data(body.prefix(length)) : nil
    }

    // MARK: - JSON-RPC

    private func handle(body: Data, reply: @escaping (Data?) -> Void) {
        KeepAwake.poke(20)
        Task { @MainActor in AgentStatus.shared.lastSeen = Date() }
        guard let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = message["method"] as? String
        else { reply(rpcError(id: nil, code: -32700, message: "parse error")); return }
        let id = message["id"]
        guard id != nil else { reply(nil); return } // notification

        switch method {
        case "initialize":
            let params = message["params"] as? [String: Any]
            let version = params?["protocolVersion"] as? String ?? "2025-03-26"
            let client = (params?["clientInfo"] as? [String: Any])?["name"] as? String
            Task { @MainActor in AgentStatus.shared.clientName = client }
            reply(rpcResult(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "Chiaro", "version": "0.1"],
            ]))
        case "ping":
            reply(rpcResult(id: id, [:]))
        case "tools/list":
            reply(rpcResult(id: id, ["tools": Self.toolDefinitions]))
        case "tools/call":
            let params = message["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let content = try await self.callTool(name, args: args)
                    reply(self.rpcResult(id: id, ["content": content, "isError": false]))
                } catch {
                    reply(self.rpcResult(id: id, [
                        "content": [["type": "text", "text": error.localizedDescription]],
                        "isError": true,
                    ]))
                }
            }
        default:
            reply(rpcError(id: id, code: -32601, message: "method not found: \(method)"))
        }
    }

    private func rpcResult(id: Any?, _ result: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id ?? NSNull(), "result": result,
        ])) ?? Data()
    }

    private func rpcError(id: Any?, code: Int, message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id ?? NSNull(),
            "error": ["code": code, "message": message],
        ])) ?? Data()
    }

    // MARK: - Tools

    struct ToolError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static let editProperties: [String: Any] = Dictionary(
        uniqueKeysWithValues: EditParameter.allCases.map { p in
            (p.rawValue, [
                "type": "number",
                "description": "range \(p.range.lowerBound)...\(p.range.upperBound)",
            ] as [String: Any])
        }
    )

    static let toolDefinitions: [[String: Any]] = [
        [
            "name": "list_photos",
            "description": "List the photos in Chiaro's open library: name, rating, whether edited, and which one is open in the editor.",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
        ],
        [
            "name": "get_edit",
            "description": "Read a photo's full EditState (all adjustment values) and rating.",
            "inputSchema": [
                "type": "object",
                "properties": ["name": ["type": "string", "description": "photo name, e.g. DSC04091"]],
                "required": ["name"],
            ],
        ],
        [
            "name": "set_edit",
            "description": "Set adjustment values on a photo. Only supplied parameters change. If the photo is open in the editor, the change renders live. Values outside a parameter's range are clamped.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "edit": ["type": "object", "properties": editProperties],
                    "reset": ["type": "boolean", "description": "reset to neutral before applying"],
                    "intent": ["type": "string", "description": "short description of what you're doing (e.g. 'warming skin tones') — shown live in the app UI"],
                ],
                "required": ["name", "edit"],
            ],
        ],
        [
            "name": "open_photo",
            "description": "Open a photo in Chiaro's edit view (brings the editing UI to that photo).",
            "inputSchema": [
                "type": "object",
                "properties": ["name": ["type": "string"]],
                "required": ["name"],
            ],
        ],
        [
            "name": "get_preview",
            "description": "Render a photo with its current edit and return a JPEG preview image.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "maxDimension": ["type": "number", "description": "longest edge in px, default 768"],
                ],
                "required": ["name"],
            ],
        ],
        [
            "name": "export",
            "description": "Export a photo at full resolution through its current edit. Returns the written file path.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "format": ["type": "string", "enum": ["jpeg", "heif", "tiff16"]],
                    "quality": ["type": "number", "description": "0.5-1.0, default 0.92"],
                ],
                "required": ["name"],
            ],
        ],
    ]

    @MainActor
    private func callTool(_ name: String, args: [String: Any]) async throws -> [[String: Any]] {
        guard let library else { throw ToolError("library unavailable") }

        func photo(_ args: [String: Any]) throws -> Photo {
            guard let name = args["name"] as? String else { throw ToolError("missing name") }
            guard let photo = library.photos.first(where: { $0.name == name }) else {
                throw ToolError("no photo named \(name) in the open library")
            }
            return photo
        }
        func text(_ value: Any) throws -> [[String: Any]] {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            return [["type": "text", "text": String(decoding: data, as: UTF8.self)]]
        }

        switch name {
        case "list_photos":
            return try text([
                "folder": library.folderURL?.path ?? "none",
                "editing": library.editing?.name ?? NSNull() as Any,
                "photos": library.photos.map {
                    ["name": $0.name, "rating": $0.rating, "hasEdits": $0.hasEdits, "isRAW": $0.isRAW]
                },
            ])
        case "get_edit":
            let p = try photo(args)
            let edit = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p.edit))
            return try text(["name": p.name, "rating": p.rating, "edit": edit])
        case "set_edit":
            let p = try photo(args)
            guard let params = args["edit"] as? [String: Any] else { throw ToolError("missing edit object") }
            var edit = (args["reset"] as? Bool == true) ? EditState.neutral : p.edit
            for (key, value) in params {
                guard let parameter = EditParameter(rawValue: key) else {
                    throw ToolError("unknown parameter \(key); valid: \(EditParameter.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                guard let number = value as? Double ?? (value as? Int).map(Double.init) else {
                    throw ToolError("\(key) must be a number")
                }
                parameter.set(number, in: &edit)
            }
            if let editor = library.activeEditor, editor.photo.url == p.url {
                library.noteAgentActivity(intent: args["intent"] as? String)
                editor.edit = edit // renders live in the UI
            } else {
                p.edit = edit
                Sidecar.write(for: p)
            }
            return try text(["applied": true, "name": p.name])
        case "open_photo":
            let p = try photo(args)
            library.edit(p)
            library.noteAgentActivity(intent: args["intent"] as? String)
            NSApp.activate(ignoringOtherApps: true)
            return try text(["opened": p.name])
        case "get_preview":
            let p = try photo(args)
            let maxDim = args["maxDimension"] as? Double ?? 768
            let url = p.url, edit = p.edit
            let jpeg = await Offload.on(Offload.render) { () -> Data? in
                guard let base = RawEngine.shared.preview(for: url) else { return nil }
                var mask: CIImage?
                if edit.blurF > 0 || edit.relight != 0 {
                    mask = PortraitEngine.shared.mask(for: url, image: base)
                }
                var out = RenderPipeline.render(base: base, edit: edit, personMask: mask)
                let scale = maxDim / Double(max(out.extent.width, out.extent.height))
                if scale < 1 { out = out.transformed(by: .init(scaleX: scale, y: scale)) }
                return RawEngine.shared.context.jpegRepresentation(
                    of: out, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]
                )
            }
            guard let jpeg else { throw ToolError("could not render \(url.lastPathComponent)") }
            return [["type": "image", "data": jpeg.base64EncodedString(), "mimeType": "image/jpeg"]]
        case "export":
            let p = try photo(args)
            var options = ExportOptions()
            switch args["format"] as? String {
            case "heif": options.format = .heif
            case "tiff16": options.format = .tiff16
            default: options.format = .jpeg
            }
            if let q = args["quality"] as? Double { options.quality = q }
            if Self.volumeIsRemovable(p.url) {
                options.destination = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Chiaro Exports")
            }
            let finalOptions = options
            let out = await Offload.on(Offload.render) { () -> Result<URL, Error> in
                Result { try Exporter.export(p, options: finalOptions) }
            }
            return try text(["exported": out.get().path])
        default:
            throw ToolError("unknown tool \(name)")
        }
    }

    private static func volumeIsRemovable(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsReadOnlyKey])
        return values?.volumeIsRemovable ?? false || values?.volumeIsEjectable ?? false || values?.volumeIsReadOnly ?? false
    }
}
