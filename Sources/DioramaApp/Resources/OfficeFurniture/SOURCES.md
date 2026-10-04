# Herman Miller furniture assets

Copyright remains with Herman Miller / MillerKnoll. These are not generically licensed assets.
The project owner explicitly confirmed permission to convert and bundle these two models
in Diorama in this task on 2026-09-29. The published website terms alone do not grant that
permission; do not treat these files as a freely redistributable asset library.

- Aeron ESD Chair, C Size, Height-Adjustable Arms:
  https://www.hermanmiller.com/resources/3d-models-and-planning-tools/product-models/individual/aeron-esd-chair-c-size-height-adjustable-arms/
- Nevi Sit-to-Stand Table, C Foot:
  https://www.hermanmiller.com/resources/3d-models-and-planning-tools/product-models/individual/nevi-sit-to-stand-table-c-foot/

Official AutoCAD 3D DWGs downloaded 2026-09-29, converted with LibreDWG 0.14 and
scripts/convert-office-furniture.py (ezdxf). The source files explicitly specify inches.
OBJ coordinates are metres, Y up; orientation and origin are normalized, proportions preserved.
Layer-based neutral materials are Diorama presentation choices, not specified product finishes.
manifest.json records source SHA-256 hashes, converted bounds, and triangle counts.

Lower-detail copies are generated with scripts/build-office-lod.py using Blender decimation.
CapybaraOfficeLow.glb derives from Diorama's existing bundled Capybara.glb, retaining its rig.
These optimization copies do not change the furniture's intended dimensions or attribution.

## TV lounge — 2026-10-02

Requested official Eames Lounge Chair–Classic and Luva Corner Sectional CAD models:
- https://www.hermanmiller.com/resources/3d-models-and-planning-tools/product-models/individual/eames-lounge-chair-classic/
- https://www.hermanmiller.com/resources/3d-models-and-planning-tools/product-models/individual/luva-modular-sofa-group-corner-sectional/

Converted with LibreDWG and `scripts/convert-lounge-furniture.py`. Source hashes,
authored metre dimensions, and triangle counts are in LoungeCAD.json. The Eames
DWG also contains a disconnected ottoman; that separate component is omitted.
Chair proportions and both complete sectionals are preserved. Cream upholstery,
black leather, and walnut shell colors are Diorama presentation choices.
`scripts/prepare-lounge-lod.py` produces the shared lower-detail meshes and the
measured LoungeDimensions.json used for placement and clearance.

The user-supplied Vintage Home Theater GLB is converted with
`scripts/prepare-office-arcade.py` (LoungeTV, 24000 triangles, width). It remains
1.9 metres wide with original proportions and textures. LoungeTV.json records
its source hash. The TV, sofas, and chairs are static decoration, with no media
playback or inferred agent activity.

## Flame Striker foosball table

User-supplied `Meshy_AI_Flame_Striker_Foosbal_1003004423_texture.glb`.
SHA-256: `c28a939b296848e249ba34784c4ee8c3dfd474c062ddd5a223920b5a32bd3bbe`.
Converted with Blender using `scripts/prepare-office-arcade.py -- INPUT .local/foosball Foosball 30000 height 0.9`.
Uniformly scaled to 0.9 m total height, preserving proportions (2.702 m wide
including handles, 2.065 m deep). Static 30,000-triangle mesh, original base-color,
metal/roughness, and normal textures. No gameplay or animations.
Placed past the seating group with a 1.2 m gap and clear floor on both playing sides.
The floor extends automatically; existing furniture placements stay unchanged.
