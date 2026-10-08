import AVFoundation
import Testing
@testable import DioramaApp

@MainActor struct KitchenSoundTests {
    @Test func everySoundVariantIsBundled() throws {
        for sound in KitchenSound.allCases {
            for variant in 0..<sound.variants {
                let url = try #require(WorkspaceCapybaraAsset.resourceBundle.url(forResource: "\(sound.rawValue)-\(variant)", withExtension: "caf", subdirectory: "KitchenSounds"))
                #expect(try AVAudioFile(forReading: url).length > 0)
            }
        }
    }

    @Test func cuesNameRealClipsAndMarkers() throws {
        let clips = try ChefAssets.shared.get().manifest.clips
        for (name, cues) in KitchenSound.cues {
            let clip = try #require(clips[name], "\(name) is not a chef clip")
            for (at, _) in cues { if case let .marker(marker) = at { #expect(clip.markers[marker] != nil, "\(name) has no \(marker) marker") } }
        }
    }

    @Test func cuesFireOnceAsTheClipPassesThem() {
        let markers: [String: Float] = ["impact": 0.1667, "impact_2": 0.6667]
        #expect(KitchenSound.crossed("working_chop", markers: markers, from: 0, to: 0.1) == [])
        #expect(KitchenSound.crossed("working_chop", markers: markers, from: 0.1, to: 0.2) == [.chop])
        #expect(KitchenSound.crossed("working_chop", markers: markers, from: 0.2, to: 0.7) == [.chop])
        // Across the loop's wrap, and a clip that just started hears its cue at 0.
        #expect(KitchenSound.crossed("walk", markers: [:], from: -0.1, to: 0.06) == [.step])
        #expect(KitchenSound.crossed("error_react", markers: [:], from: -1, to: 0.01) == [.error])
        #expect(KitchenSound.crossed("idle_available", markers: [:], from: -1, to: 1) == [])
    }
}
