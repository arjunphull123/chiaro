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

    private struct HTTPRequest {
        var method: String
        var path: String
        var origin: String?
        var body: Data
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self, error == nil else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parseRequest(buffer) {
                self.route(request) { status, payload in
                    var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n"
                    if status.hasPrefix("405") { head += "Allow: POST\r\n" }
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

    /// MCP streamable-HTTP requirements: validate Origin (DNS-rebinding defense),
    /// POST-only (no SSE stream offered), single /mcp endpoint.
    private func route(_ request: HTTPRequest, reply: @escaping (String, Data) -> Void) {
        if let origin = request.origin,
           !(origin.contains("127.0.0.1") || origin.contains("localhost")) {
            reply("403 Forbidden", Data("{\"error\":\"origin not allowed\"}".utf8))
            return
        }
        guard request.path == "/mcp" || request.path == "/mcp/" else {
            reply("404 Not Found", Data("{\"error\":\"unknown path\"}".utf8))
            return
        }
        guard request.method == "POST" else {
            reply("405 Method Not Allowed", Data("{\"error\":\"POST only; SSE stream not offered\"}".utf8))
            return
        }
        handle(body: request.body) { response in
            if let response { reply("200 OK", response) } else { reply("202 Accepted", Data()) }
        }
    }

    /// Returns the request once headers + Content-Length bytes have fully arrived.
    private static func parseRequest(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        let lines = head.split(separator: "\r\n")
        let requestParts = lines.first?.split(separator: " ") ?? []
        let method = requestParts.count > 0 ? String(requestParts[0]) : "POST"
        let path = requestParts.count > 1 ? String(requestParts[1]) : "/mcp"
        func header(_ name: String) -> String? {
            lines.first { $0.lowercased().hasPrefix("\(name):") }
                .map { $0.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces) }
        }
        let length = header("content-length").flatMap(Int.init) ?? 0
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return nil }
        return HTTPRequest(
            method: method, path: path,
            origin: header("origin"), body: Data(body.prefix(length))
        )
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
            // Version negotiation per spec: echo the client's version if we support
            // it, otherwise answer with the latest we do.
            let supported = ["2024-11-05", "2025-03-26", "2025-06-18"]
            let requested = params?["protocolVersion"] as? String ?? "2025-03-26"
            let version = supported.contains(requested) ? requested : "2025-06-18"
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

    private static let editProperties: [String: Any] = {
        var props = Dictionary(
            uniqueKeysWithValues: EditParameter.allCases.map { p in
                (p.rawValue, [
                    "type": "number",
                    "description": "range \(p.range.lowerBound)...\(p.range.upperBound)",
                ] as [String: Any])
            }
        )
        props["crop"] = [
            "type": "object",
            "properties": ["x": ["type": "number"], "y": ["type": "number"],
                           "w": ["type": "number"], "h": ["type": "number"]],
            "description": "normalized crop {x,y,w,h}, 0-1, y from top, applied after straighten",
        ] as [String: Any]
        props["blurMode"] = [
            "type": "string",
            "enum": ["subject", "person", "depth"],
            "description": "what stays sharp: subject (any lifted foreground), person (people only), or depth (focus plane — pair with focusDepth 0 near…1 far and focusRange; needs the depth model downloaded in the app)",
        ]
        props["curve"] = [
            "type": "array",
            "items": ["type": "array", "items": ["type": "number"]],
            "description": "tone curve control points [[x,y],...], each 0-1, sorted by x, including endpoints — e.g. a gentle S: [[0,0],[0.25,0.2],[0.75,0.8],[1,1]]",
        ] as [String: Any]
        return props
    }()

    /// Onboarding prompt for the Connect-agent popover. Lives beside
    /// toolDefinitions so tool renames can't silently drift out of it.
    static var onboardingPrompt: String {
        let url = "http://127.0.0.1:\(shared.port == 0 ? preferredPort : shared.port)/mcp"
        return """
        You are being connected to Chiaro, a RAW photo editor running on this Mac. \
        It serves MCP at \(url) (streamable HTTP; discovery file at ~/.chiaro/mcp.json).

        1. Connect using your MCP support. Claude Code: `claude mcp add --transport http chiaro \(url)`. \
        Other agents: add an HTTP MCP server named "chiaro" with that URL to your MCP configuration.
        2. Confirm the connection by calling the list_photos tool — Chiaro shows you as \
        connected the moment your first request arrives.
        3. Then tell the user you are connected, briefly summarize what is in their library, \
        and ask what they would like to do.

        Working notes: get_edit reads a photo's settings. get_preview returns the photo rendered \
        with its current edit — look before and after every change. set_edit changes only the \
        parameters you send and accepts an `intent` string that is shown to the user live. \
        open_photo displays a photo in the editor so the user can watch. export writes the \
        finished file. All edits are non-destructive and render live.
        """
    }

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
            "name": "list_presets",
            "description": "Names of the available presets (built-in and user-saved). Presets carry tone and color only — geometry and portrait settings stay put.",
            "inputSchema": ["type": "object", "properties": [:]],
        ],
        [
            "name": "apply_preset",
            "description": "Apply a preset to a photo by name (see list_presets). Renders live if the photo is open.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "preset": ["type": "string"],
                ],
                "required": ["name", "preset"],
            ],
        ],
        [
            "name": "set_rating",
            "description": "Star-rate a photo (0-5). Ratings persist in the sidecar and show in the library — the culling workflow: review previews, rate the keepers.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "rating": ["type": "integer", "minimum": 0, "maximum": 5],
                ],
                "required": ["name", "rating"],
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
                    "format": ["type": "string", "enum": ["jpeg", "heif", "tiff", "original"]],
                    "quality": ["type": "number", "description": "0.5-1.0, default 0.85"],
                    "maxDimension": ["type": "number", "description": "longest edge in px; omit for full resolution"],
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

        logAction(name, args: args, library: library)
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
        case "list_presets":
            return try text(["presets": PresetStore.shared.all.map(\.name)])
        case "apply_preset":
            let p = try photo(args)
            guard let presetName = args["preset"] as? String,
                  let preset = PresetStore.shared.all.first(where: { $0.name == presetName }) else {
                throw ToolError("unknown preset; valid: \(PresetStore.shared.all.map(\.name).joined(separator: ", "))")
            }
            if let editor = library.activeEditor, editor.photo.url == p.url {
                library.noteAgentActivity(intent: "applying \(presetName)")
                editor.edit = preset.applied(to: editor.edit)
            } else {
                p.edit = preset.applied(to: p.edit)
                Sidecar.write(for: p)
            }
            return try text(["applied": presetName, "name": p.name])
        case "set_rating":
            let p = try photo(args)
            guard let rating = args["rating"] as? Int, (0...5).contains(rating) else {
                throw ToolError("rating must be an integer 0-5")
            }
            p.rating = rating
            Sidecar.write(for: p)
            return try text(["applied": true, "name": p.name, "rating": rating])
        case "list_presets":
            return try text(["presets": PresetStore.shared.all.map(\.name)])
        case "apply_preset":
            let p = try photo(args)
            guard let presetName = args["preset"] as? String,
                  let preset = PresetStore.shared.all.first(where: { $0.name == presetName }) else {
                throw ToolError("unknown preset; valid: \(PresetStore.shared.all.map(\.name).joined(separator: ", "))")
            }
            if let editor = library.activeEditor, editor.photo.url == p.url {
                library.noteAgentActivity(intent: "applying \(presetName)")
                editor.edit = preset.applied(to: editor.edit)
            } else {
                p.edit = preset.applied(to: p.edit)
                Sidecar.write(for: p)
            }
            return try text(["applied": presetName, "name": p.name])
        case "set_rating":
            let p = try photo(args)
            guard let rating = args["rating"] as? Int, (0...5).contains(rating) else {
                throw ToolError("rating must be an integer 0-5")
            }
            p.rating = rating
            Sidecar.write(for: p)
            return try text(["applied": true, "name": p.name, "rating": rating])
        case "set_edit":
            let p = try photo(args)
            guard let params = args["edit"] as? [String: Any] else { throw ToolError("missing edit object") }
            var edit = (args["reset"] as? Bool == true) ? EditState.neutral : p.edit
            for (key, value) in params {
                if key == "crop" {
                    guard let dict = value as? [String: Any],
                          let x = dict["x"] as? Double, let y = dict["y"] as? Double,
                          let w = dict["w"] as? Double, let h = dict["h"] as? Double,
                          w > 0.05, h > 0.05
                    else { throw ToolError("crop must be {x,y,w,h} normalized 0-1") }
                    edit.crop = CropRect(
                        x: x.clamped(to: 0...0.95), y: y.clamped(to: 0...0.95),
                        w: w.clamped(to: 0.05...1), h: h.clamped(to: 0.05...1)
                    )
                    continue
                }
                if key == "blurMode" || key == "depthBlur" {
                    if let raw = value as? String, let mode = BlurMode(rawValue: raw) {
                        edit.blurMode = mode
                    } else if let flag = value as? Bool {
                        edit.blurMode = flag ? .depth : .subject
                    } else {
                        throw ToolError("blurMode must be one of subject, person, depth")
                    }
                    continue
                }
                if key == "curve" {
                    guard let raw = value as? [[Any]] else { throw ToolError("curve must be [[x,y],...]") }
                    let pts = raw.compactMap { pair -> CurvePoint? in
                        guard pair.count == 2,
                              let x = (pair[0] as? Double) ?? (pair[0] as? Int).map(Double.init),
                              let y = (pair[1] as? Double) ?? (pair[1] as? Int).map(Double.init)
                        else { return nil }
                        return CurvePoint(x: x.clamped(to: 0...1), y: y.clamped(to: 0...1))
                    }
                    guard pts.count >= 2 else { throw ToolError("curve needs at least 2 points") }
                    edit.curve = pts.sorted { $0.x < $1.x }
                    continue
                }
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
                    mask = PortraitEngine.shared.mask(
                        for: url, image: base,
                        kind: edit.blurMode == .person ? .person : .subject)
                }
                let depth = edit.blurMode == .depth && edit.blurF > 0
                    ? DepthEngine.shared.depthMap(for: url, image: base) : nil
                var out = RenderPipeline.render(base: base, edit: edit, personMask: mask, depthMap: depth)
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
            case "tiff", "tiff16": options.format = .tiff
            case "original": options.format = .original
            default: options.format = .jpeg
            }
            if let maxDim = args["maxDimension"] as? Double { options.maxDimension = maxDim }
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

    @MainActor
    private func logAction(_ tool: String, args: [String: Any], library: Library) {
        let name = args["name"] as? String ?? ""
        let text: String
        switch tool {
        case "list_photos": text = "surveyed the library"
        case "get_edit": text = "read the settings of \(name)"
        case "get_preview": text = "looked at \(name)"
        case "open_photo": text = "opened \(name)"
        case "set_edit": text = (args["intent"] as? String).map { "\(name) — \($0)" } ?? "adjusted \(name)"
        case "set_rating": text = "rated \(name)"
        case "apply_preset": text = "applied \((args["preset"] as? String) ?? "a preset") to \(name)"
        case "export": text = "exported \(name)"
        default: text = "\(tool) \(name)"
        }
        AgentStatus.shared.log(text)
    }

    private static func volumeIsRemovable(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsReadOnlyKey])
        return values?.volumeIsRemovable ?? false || values?.volumeIsEjectable ?? false || values?.volumeIsReadOnly ?? false
    }
}
