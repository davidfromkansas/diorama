import Foundation
import simd

/// Runtime contract shipped next to `chef-animated.glb` (see assets/chef/README.md).
/// glTF has no events, so clip markers and prop attach transforms only live here.
nonisolated struct ChefManifest: Decodable, Sendable {
    struct Clip: Decodable {
        let duration: Float
        let loop: Bool
        /// Normalised 0…1 positions within the clip.
        let markers: [String: Float]
        let nominalSpeed: Float?
        enum CodingKeys: String, CodingKey { case duration, loop, markers, nominalSpeed = "nominal_speed" }
    }
    struct Attach: Decodable {
        let socket: String
        let position: [Float]
        let quaternion: [Float] // x, y, z, w in the socket's local frame
        var simdPosition: SIMD3<Float> { SIMD3(position[0], position[1], position[2]) }
        var simdQuaternion: simd_quatf { simd_quatf(ix: quaternion[0], iy: quaternion[1], iz: quaternion[2], r: quaternion[3]) }
    }
    struct Stations: Decodable {
        let counterTop: Float
        let boardTop: Float
        let counterFrontFromRoot: Float
        enum CodingKeys: String, CodingKey { case counterTop = "counter_top", boardTop = "board_top", counterFrontFromRoot = "counter_front_from_root" }
    }
    let height: Float
    let clips: [String: Clip]
    let attach: [String: [String: Attach]]
    let stations: Stations

    @MainActor static func load() throws -> ChefManifest {
        guard let url = WorkspaceCapybaraAsset.resourceBundle.url(forResource: "chef-manifest", withExtension: "json", subdirectory: "Chef") else {
            throw WorkspaceCapybaraAsset.AssetError.invalid("Bundled chef manifest is missing")
        }
        return try JSONDecoder().decode(ChefManifest.self, from: Data(contentsOf: url))
    }
}

/// Hand props a chef can hold. Each maps to a node in `chef-props.glb` and the clip whose
/// grip the manifest fitted it to.
nonisolated enum ChefProp: String, CaseIterable, Sendable {
    case card, book, knife, spoon, plate, ticket, mug, cloche
    var node: String {
        switch self {
        case .ticket: "prop_ticket"
        case .mug: "prop_mug"
        case .cloche: "prop_cloche"
        case .card: "prop_recipe_card"
        case .book: "prop_cookbook"
        case .knife: "prop_knife"
        case .spoon: "prop_spoon"
        case .plate: "prop_plate"
        }
    }
    var socket: String {
        switch self {
        case .card, .book, .ticket: "socket_hand.L"
        case .knife, .spoon, .mug, .cloche: "socket_hand.R"
        case .plate: "socket_carry"
        }
    }
    var fitClip: String {
        switch self {
        case .card: "planning_recipe"
        case .book: "researching_book"
        case .knife: "working_chop"
        case .spoon: "testing_dish"
        case .plate: "carry_idle"
        case .ticket: "read_ticket"
        case .mug: "sit_sip"
        case .cloche: "cover_dish"
        }
    }
}
