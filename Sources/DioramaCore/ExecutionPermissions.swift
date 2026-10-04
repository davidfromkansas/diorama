import Foundation

extension ApprovalReviewChoice {
    public var claudeMode: String? {
        switch self {
        case .inherit: nil
        case .user: "default"
        case .autoReview: "auto"
        case .acceptEdits: "acceptEdits"
        case .fullAccess: "bypassPermissions"
        }
    }
    public static func claude(_ mode: String?) -> Self? {
        switch mode {
        case "default", "manual": .user
        case "auto": .autoReview
        case "acceptEdits": .acceptEdits
        case "bypassPermissions": .fullAccess
        default: nil
        }
    }
}

extension ExecutedTask {
    public var reportedPermissionChoice: ApprovalReviewChoice? {
        if provider == .claude { return .claude(approvalPolicy.string) }
        if sandbox["type"].string == "workspaceWrite", approvalPolicy.string == "on-request" {
            return approvalReviewer == "auto_review" ? .autoReview : approvalReviewer == "user" ? .user : nil
        }
        return .reported(reviewer: approvalReviewer, policy: approvalPolicy, sandbox: sandbox)
    }
}

extension ExecutionController {
    public func permissionUnavailable(_ choice: ApprovalReviewChoice, model: String) -> String? {
        if model.hasPrefix("claude/") {
            return choice == .autoReview && models.first(where: { $0.id == model })?.supportsAutoMode == false ? "Automatic review is unavailable for this model" : nil
        }
        let policy = choice == .fullAccess ? "never" : "on-request"
        if case .array(let allowed) = permissionRequirements["allowedApprovalPolicies"], !allowed.contains(.string(policy)) { return "This approval policy is restricted by managed settings" }
        if choice == .fullAccess, case .array(let allowed) = permissionRequirements["allowedSandboxModes"], !allowed.contains(.string("danger-full-access")) { return "Full access is restricted by managed settings" }
        let required = permissionRequirements["autoReview"]["requiredOnModels"].array.compactMap(\.string)
        if choice != .autoReview && (required.contains(model) || required.contains("*")) { return "Automatic review is required for this model" }
        return nil
    }
    /// No prompt is submitted here. Provider acknowledgement is persisted before delivery.
    func preparePermissions(id: String, choice: ApprovalReviewChoice = .inherit, model: String = "", mode: String? = nil) async throws {
        guard changingPermissions.insert(id).inserted else { throw ExecutionRPCRejection("A permission change is already in progress") }
        defer { changingPermissions.remove(id) }
        guard var task = tasks[id], task.attached else { throw ExecutionRPCRejection("Reconnect before choosing permissions.") }
        guard !requests.values.contains(where: { $0.threadID == id && $0.isBlocking }) else { throw ExecutionRPCRejection("Resolve the outstanding request before changing permissions.") }
        if task.permissionsUnconfirmed && choice == .inherit { throw ExecutionRPCRejection("Permission outcome is unconfirmed. Select a mode to reconcile before sending.") }
        let moved = task.permissionFolder.map { URL(fileURLWithPath: $0).standardizedFileURL != URL(fileURLWithPath: task.folder).standardizedFileURL } ?? false
        if moved && choice == .inherit { throw ExecutionRPCRejection("The working folder changed. Choose permissions for the new workspace before sending.") }
        let selected = model.isEmpty ? task.model : model
        // Inherit keeps live provider settings. A bookmark is not a request to change them.
        // Leaving Claude Plan Mode retains the existing explicit execution-mode transition.
        let leavingClaudePlan = task.provider == .claude && task.approvalPolicy.string == "plan" && mode != "plan"
        let desired = choice == .inherit ? (leavingClaudePlan ? task.permissionPreference : nil) : choice
        if let desired, let reason = permissionUnavailable(desired, model: selected) { throw ExecutionRPCRejection(reason) }
        guard let desired else {
            if task.provider == .claude, task.approvalPolicy.string == "plan", mode != "plan" {
                throw ExecutionRPCRejection("Choose execution permissions before leaving this imported Plan Mode session.")
            }
            guard task.approvalPolicy != .null, task.provider == .claude || task.sandbox != .null || task.activePermissionProfile != .null else {
                throw ExecutionRPCRejection("Permissions unconfirmed. Choose a permission mode before sending.")
            }
            if task.permissionNotice == "Provider permissions differ from your saved choice. Select a mode before sending." {
                tasks[id]?.permissionNotice = nil
            }
            return // Preserve known custom settings without replacing them with a preset.
        }
        guard desired != .inherit, task.provider == .claude || desired != .acceptEdits else {
            throw ExecutionRPCRejection("This permission option is not supported by the selected provider.")
        }
        if task.provider == .claude {
            let target = mode == "plan" ? "plan" : desired.claudeMode!
            do {
                let reply = try await transport.request("diorama/permissions/set", .object([
                    "threadId": .string(id), "model": .string(selected), "permissionMode": .string(target),
                    "executionPermissionMode": .string(desired.claudeMode!)
                ]))
                guard let effective = reply["permissionMode"].string, effective == target else {
                    throw ExecutionRPCRejection("Claude did not confirm the requested permissions. No message was sent.")
                }
                task = tasks[id] ?? task
                task.approvalPolicy = .string(effective); task.sandbox = .null
                task.model = reply["model"].string ?? selected
            } catch {
                tasks[id]?.permissionsUnconfirmed = true
                tasks[id]?.permissionNotice = "Claude permission change failed: \(error.localizedDescription). No message was sent."
                throw ExecutionRPCRejection(tasks[id]!.permissionNotice!)
            }
        } else if choice != .inherit || task.reportedPermissionChoice == nil {
            var params: [String: WireValue] = ["threadId": .string(id), "excludeTurns": .bool(true),
                "approvalPolicy": .string(desired == .fullAccess ? "never" : "on-request"),
                "approvalsReviewer": .string(desired == .autoReview ? "auto_review" : "user")]
            // Reviewer-only changes keep existing profiles, network policy, and writable roots.
            if desired == .fullAccess { params["sandbox"] = .string("danger-full-access") }
            else if task.sandbox["type"].string != "workspaceWrite", task.activePermissionProfile == .null {
                params["sandbox"] = .string("workspace-write")
            }
            if moved, desired != .fullAccess {
                params["cwd"] = .string(task.folder)
                params["sandbox"] = .string("workspace-write")
                params["config"] = .object(["sandbox_workspace_write.writable_roots": .array([.string(task.folder)])])
            }
            do {
                let reply = try await transport.request("thread/resume", .object(params))
                guard reply["thread"]["id"].string == id else { throw ExecutionRPCRejection("Unexpected permission acknowledgement") }
                task = tasks[id] ?? task
                applySettings(reply, to: &task)
                tasks[id] = task // Preserve actual settings even when they conflict with the request.
                guard task.approvalReviewer == (desired == .autoReview ? "auto_review" : "user"),
                      task.approvalPolicy.string == (desired == .fullAccess ? "never" : "on-request"),
                      desired != .fullAccess || task.sandbox["type"].string == "dangerFullAccess" else {
                    throw ExecutionRPCRejection("Codex did not confirm the requested permissions.")
                }
            } catch {
                tasks[id]?.permissionsUnconfirmed = true
                tasks[id]?.permissionNotice = "Permission change could not be confirmed. No message was sent. \(error.localizedDescription)"
                throw ExecutionRPCRejection(tasks[id]!.permissionNotice!)
            }
        }
        guard tasks[id]?.attached == true, tasks[id]?.phase.active != true else { throw ExecutionRPCRejection("Conversation changed while applying permissions. Reconnect before sending.") }
        task.permissionsUnconfirmed = false
        task.permissionPreference = desired; task.permissionFolder = task.folder; task.permissionNotice = nil
        tasks[id] = task
        persist()
    }
}
