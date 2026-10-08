# Kitchen food

Dishes the kitchen's chefs prepare. Each task gets one dish at random (equal odds): it sits on the
chef's cutting board while chopping, in front of the chef at the tasting station, and is the plate
carried to and presented at the serving window.

## Add a dish

1. Put a static, textured `.glb` in `source/` named after the dish id (e.g. `source/tacos.glb`).
2. Run `assets/food/build.sh tacos` (or `assets/food/build.sh` for all). Needs Blender 5.x.
3. Rebuild the app. Every `Sources/DioramaApp/Resources/Food/*.glb` is picked up automatically.

`build.sh` decimates to 15k triangles (`FACES=`), resizes textures to 1024 px (`TEXTURE=`), centres
the dish, puts its base at 0 and scales its widest side to 1.0. The app sizes it from there.

## Sources (user-supplied, 2026-10-04)

| id | original file | SHA-256 |
|---|---|---|
| cheeseburger | Meshy_AI_Cheeseburger_on_a_Pla_1005043053_texture.glb | 317fa6bc13839dd5aec82be006acc611105cede42b23f82b4b5220541c2286a9 |
| peking_duck | peking_duck.glb | 84aa4492624a541dd545b05cd5733b70373d14fff3cc74452b03dc02312883bb |
| pizza | pizza.glb | 2097bcb1eab0dc03abaeeb7f756f24f9a65e29396167e8c1d5bbb6b30b25ce53 |
| spaghetti | spaghetti.glb | 07e3358e942aacf3901c55c7ff65f1504aa3db5d22e04b5fac73b954c863abf3 |
