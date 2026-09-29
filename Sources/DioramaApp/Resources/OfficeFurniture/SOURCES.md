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
