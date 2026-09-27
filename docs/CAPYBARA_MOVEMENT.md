# Capybara movement in the workspace

The **Movement Lab** button in the workspace now places the supplied capybara directly into `WorkspaceSceneNSView`: the same SceneKit renderer, camera, floor, library and desks used by the app. It is not a WebView overlay or a recreation of the room. The lab can also be opened independently with `scripts/build-capybara-lab.sh`, which builds `dist/Diorama Capybara Lab.app` without touching the installed Diorama app or starting agent sessions. A SwiftPM run accepts `--capybara-lab`.

Click open floor to move; switch Walk/Run while travelling; use Stop, Turn left/right, or Reset. Drag and zoom remain available. Toggling the lab off restores the prior workspace camera. Agent labels are hidden while testing so they do not cover the moving character. Blocked destinations are visibly rejected. Every agent desk now uses the supplied capybara with an independent skeleton. The seated pose fits the chair, and bind-relative arm/head rotations preserve typing, attention waves, celebration and failure gestures.

## Motion direction

Reference footage:

- [Nintendo's Animal Crossing: New Horizons video guide](https://play.nintendo.com/media/videos/animal-crossing-new-horizons-video-guide/)
- [Nintendo's official Pokémon Pokopia extended trailer](https://www.nintendo.com/us/whatsnew/catch-a-cozy-new-video-about-pokemon-pokopia/)

These are art-direction references, not motion data or claims that their proprietary movement algorithms were reproduced. The goals are a readable silhouette, short alternating steps, restrained vertical bounce, an expressive but stable large head, and quick response with believable weight. This pass adds head anticipation, a small acceleration/run lean, damped turn banking, a short settle after stopping, phase-matched gait blending and foot planting. The original mesh, topology, and embedded textures remain unchanged.

## Native architecture

`WorkspaceCapybaraAsset` reads the bundled validated GLB directly into SceneKit geometry, PBR textures, `SCNSkinner`, independent per-character skeleton nodes and animation samples. Geometry/materials are shared, but bones are not. This reader supports the exact packaged asset's linear/step channels, not arbitrary user-supplied glTF assets or external textures.

`WorkspaceCapybaraMotion` owns world travel, bounded steering velocity, acceleration/braking, gait phase, pose sampling/blending, head/torso offsets, and two-bone foot IK. Planted feet retain world-space anchors. Pelvis reach adjustment prevents short legs from overextending during pivots. Swing targets keep the ankle above the floor. The controller runs in bounded 120 Hz substeps with a 60 Hz main-run-loop timer in the active lab; it stops when the workspace is inactive or dismantled. Reduced motion removes head/torso decoration and freezes idle micro-motion while preserving user-requested locomotion.

`WorkspaceCapybaraNavigation` performs A* on the workspace floor and then removes unnecessary waypoints using segment visibility. Desk/chair and library footprints are inflated for the capybara's body width. Every movement step also checks the segment against obstacles. This is a planar navigation system; it does not yet handle stairs, terrain, moving crowds or dynamically carried objects.

The normal workspace continues using its previous rendering lifecycle when the lab is off. Lab resource/load failures are shown in its status line instead of silently substituting another avatar.

## Verification

```sh
swift test --scratch-path /tmp/diorama-capybara-build --no-parallel \
  --filter 'WorkspaceCapybaraTests|WorkspaceAgentTests|WorkspaceMotionTests'
```

Twenty-two tests across these suites cover the bundled skinned model, independent skeleton instances, furniture avoidance, blocked goals, arrival at 30/60/120 Hz, interrupted turns, planted-foot residual below 2 mm on the tested route, suspension/camera restoration, and existing workspace camera/activity behavior. The GLB's original asset validation and the ten browser-controller tests remain in `assets/capybara-motion`.

With `DIORAMA_CAPTURE_CAPYBARA=1`, the native rendering test writes a deterministic 60 fps, 12-second sequence to `/tmp/diorama-capybara-workspace/frame-%04d.png`. It includes idle, walking, switching to running around the desk, stopping and a turn. A review copy is at `artifacts/capybara-workspace/movement.mp4`. Ordinary test runs render seven representative frames to keep the main actor responsive. Interactive testing additionally exercised actual floor clicks, gait switching and blocked destinations in the packaged native lab.

This is a measurable locomotion foundation toward the requested game-quality bar, not a declaration of finished character animation. Deep hip/knee deformation, foot roll and the final step into idle still deserve further art-direction polish; carrying, facial controls and animated transitions between sitting and roaming remain future work. Agent desk poses and gestures are integrated; roaming remains available through Movement Lab.
