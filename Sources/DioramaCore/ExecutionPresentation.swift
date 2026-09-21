import Foundation

public struct ExecutionPlanStep: Identifiable, Sendable, Equatable {
    public let id: Int
    public let text: String
    public let status: String
    public init(id: Int, text: String, status: String) { self.id = id; self.text = text; self.status = status }
    public var label: String {
        switch status { case "completed": "Done"; case "inProgress": "In progress"; case "pending": "Pending"; default: "Unknown" }
    }
}

/// A turn snapshot, not the repository's complete working-tree diff.
public struct ExecutionWork: Sendable {
    public var turnID: String?
    public var explanation: String?
    public var plan: [ExecutionPlanStep] = []
    public var diff = ""
    public var files: [ExecutionDiffFile] { ExecutionDiffFile.parse(diff) }
    public init() {}
}

public struct ExecutionDiffFile: Identifiable, Sendable, Equatable {
    public let id: Int
    public let path: String
    public let diff: String
    public var additions: Int { diff.components(separatedBy: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count }
    public var deletions: Int { diff.components(separatedBy: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count }
    public static func parse(_ diff: String) -> [Self] {
        guard !diff.isEmpty else { return [] }
        var sections: [[String]] = []
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git ") || sections.isEmpty { sections.append([]) }
            sections[sections.count - 1].append(line)
        }
        return sections.enumerated().map { index, lines in
            let newPath = lines.first { $0.hasPrefix("+++ ") }.map { String($0.dropFirst(4)) }
            let oldPath = lines.first { $0.hasPrefix("--- ") }.map { String($0.dropFirst(4)) }
            let raw = (newPath == "/dev/null" ? oldPath : newPath) ?? lines.first ?? "Changes"
            let path = raw.hasPrefix("a/") || raw.hasPrefix("b/") ? String(raw.dropFirst(2)) : raw
            return Self(id: index, path: path, diff: lines.joined(separator: "\n"))
        }
    }
}

public struct ApprovalDecision: Identifiable, Sendable {
    public let value: WireValue
    public var id: String { value.pretty }
    public var title: String {
        if let s = value.string {
            return ["accept": "Allow once", "acceptForSession": "Allow for session", "decline": "Deny", "cancel": "Cancel turn"][s] ?? s
        }
        if value["acceptWithExecpolicyAmendment"] != .null { return "Allow and save command rule" }
        return "Save network rule"
    }
    public var scope: String? {
        if value["acceptWithExecpolicyAmendment"] != .null { return "Persistent rule: future matching commands may run without prompting.\n" + value["acceptWithExecpolicyAmendment"].pretty }
        if value["applyNetworkPolicyAmendment"] != .null { return "Persistent network rule for future requests.\n" + value["applyNetworkPolicyAmendment"].pretty }
        return nil
    }
    public init?(_ value: WireValue) {
        if let s = value.string {
            guard ["accept", "acceptForSession", "decline", "cancel"].contains(s) else { return nil }
        } else {
            guard value.object.count == 1,
                  value["acceptWithExecpolicyAmendment"] != .null || value["applyNetworkPolicyAmendment"] != .null else { return nil }
        }
        self.value = value
    }
}

/// Typed MCP form values. Unsupported open-ended schemas stay visible but cannot be accepted.
public struct ElicitationField: Identifiable, Sendable {
    public let id: String
    public let schema: WireValue
    public let required: Bool
    public var title: String { schema["title"].string ?? id }
    public var type: String { schema["type"].string ?? "unknown" }
    public var choices: [(value: String, title: String)] {
        let source = type == "array" ? schema["items"] : schema
        let titled = source["oneOf"].array + source["anyOf"].array
        if !titled.isEmpty { return titled.compactMap { option in option["const"].string.map { ($0, option["title"].string ?? $0) } } }
        return source["enum"].array.enumerated().compactMap { i, v in
            v.string.map { ($0, source["enumNames"].array.indices.contains(i) ? source["enumNames"].array[i].string ?? $0 : $0) }
        }
    }
    public var supported: Bool {
        let allowed: Set<String> = ["type", "title", "description", "default", "enum", "enumNames", "oneOf", "items", "minItems", "maxItems", "minimum", "maximum", "minLength", "maxLength", "format"]
        return Set(schema.object.keys).isSubset(of: allowed) && ["string", "number", "integer", "boolean", "array"].contains(type) && (type != "array" || !choices.isEmpty)
    }
    public func validate(_ value: WireValue) throws {
        guard supported else { throw AppServerFailure("Unsupported field: \(title)") }
        func bound(_ key: String) -> Double? { if case .number(let n) = schema[key] { return n }; return nil }
        func check(_ valid: Bool) throws { if !valid { throw AppServerFailure("Check \(title): value does not match the requested format or limits") } }
        switch type {
        case "boolean": if case .bool = value {} else { try check(false) }
        case "number", "integer":
            guard case .number(let n) = value else { try check(false); return }
            try check(n.isFinite && (type != "integer" || n.rounded() == n) && n >= (bound("minimum") ?? -.infinity) && n <= (bound("maximum") ?? .infinity))
        case "array":
            guard case .array(let a) = value else { try check(false); return }
            let selected = a.compactMap(\.string)
            try check(selected.count == a.count && Set(selected).count == selected.count && selected.allSatisfy { s in choices.contains { $0.value == s } } && Double(a.count) >= (bound("minItems") ?? 0) && Double(a.count) <= (bound("maxItems") ?? .infinity))
        default:
            guard let s = value.string else { try check(false); return }
            try check(Double(s.unicodeScalars.count) >= (bound("minLength") ?? 0) && Double(s.unicodeScalars.count) <= (bound("maxLength") ?? .infinity))
            if !choices.isEmpty { try check(choices.contains { $0.value == s }) }
            switch schema["format"].string {
            case "email": try check(s.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil)
            case "uri": try check(URL(string: s)?.scheme != nil)
            case "date":
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
                try check(f.date(from: s).map { f.string(from: $0) == s } == true)
            case "date-time":
                let f = ISO8601DateFormatter(); let plain = f.date(from: s); f.formatOptions.insert(.withFractionalSeconds)
                try check(plain != nil || f.date(from: s) != nil)
            case nil: break
            default: try check(false)
            }
        }
    }
}

public extension ExecutionRequest {
    var isElicitation: Bool { method == "mcpServer/elicitation/request" }
    var isBlocking: Bool { isInput ? params["isBlocking"] != .bool(false) : params["turnId"].string != nil }
    var approvalDecisions: [ApprovalDecision] {
        if method == "item/commandExecution/requestApproval", params["availableDecisions"] != .null {
            return params["availableDecisions"].array.compactMap(ApprovalDecision.init)
        }
        var values: [WireValue] = ["accept", "acceptForSession", "decline", "cancel"].map(WireValue.string)
        if method == "item/commandExecution/requestApproval" {
            if case .array = params["proposedExecpolicyAmendment"] {
                values.append(.object(["acceptWithExecpolicyAmendment": .object(["execpolicy_amendment": params["proposedExecpolicyAmendment"]])]))
            }
            for amendment in params["proposedNetworkPolicyAmendments"].array {
                values.append(.object(["applyNetworkPolicyAmendment": .object(["network_policy_amendment": amendment])]))
            }
        }
        return values.compactMap(ApprovalDecision.init)
    }
    var elicitationFields: [ElicitationField] {
        let required = params["requestedSchema"]["required"].array.compactMap(\.string)
        return params["requestedSchema"]["properties"].object.sorted { $0.key < $1.key }.map { ElicitationField(id: $0.key, schema: $0.value, required: required.contains($0.key)) }
    }
    var supportsElicitationForm: Bool {
        let schema = params["requestedSchema"]
        return ["form", "openai/form", "openaiForm"].contains(params["mode"].string ?? "") && schema["type"].string == "object" && Set(schema.object.keys).isSubset(of: ["type", "properties", "required", "$schema"]) && elicitationFields.allSatisfy(\.supported)
    }
    func validateElicitation(_ result: WireValue) throws {
        guard let action = result["action"].string, ["accept", "decline", "cancel"].contains(action) else { throw AppServerFailure("Choose an elicitation action") }
        if action != "accept" { guard result["content"] == .null else { throw AppServerFailure("Declined forms cannot submit content") }; return }
        if params["mode"].string == "url" { guard result["content"] == .null else { throw AppServerFailure("URL requests do not take form content") }; return }
        guard supportsElicitationForm, case .object(let values) = result["content"], Set(values.keys).isSubset(of: Set(elicitationFields.map(\.id))) else { throw AppServerFailure("This connector form is not supported") }
        for field in elicitationFields {
            guard let value = values[field.id] else { if field.required { throw AppServerFailure("Complete \(field.title)") }; continue }
            try field.validate(value)
        }
    }
}
