import Testing
@testable import DioramaCore
struct PermissionPresetTests {
    @Test func presetsAndUnknownSettings() {
        #expect(ApprovalReviewChoice.inherit.overrides(folder: "/tmp").isEmpty)
        for choice in [ApprovalReviewChoice.user, .autoReview, .fullAccess] {
            let values = choice.overrides(folder: "/tmp/project")
            #expect(ApprovalReviewChoice.reported(reviewer: values["approvalsReviewer"]?.string, policy: values["approvalPolicy"]!, sandbox: values["sandboxPolicy"]!) == choice)
            if choice == .fullAccess {
                #expect(values["approvalPolicy"]?.string == "never")
                #expect(values["sandboxPolicy"]?["type"].string == "dangerFullAccess")
            } else {
                #expect(values["sandboxPolicy"]?["writableRoots"].array.first?.string == "/tmp/project")
                #expect(values["sandboxPolicy"]?["networkAccess"].bool == false)
            }
        }
        #expect(ApprovalReviewChoice.reported(reviewer: "user", policy: .null, sandbox: .null) == nil)
        #expect(ApprovalReviewChoice.reported(reviewer: "user", policy: .string("never"), sandbox: .object(["type": .string("workspaceWrite")])) == nil)
    }
}
