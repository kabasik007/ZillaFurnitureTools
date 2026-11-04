# Zilla Furniture Tools

SketchUp extension for checking sheet-material joints and placing **removable drilling guides**. Current version: **0.3.0**.

## Install

1. Run `python tools/build_rbz.py` from this repository.
2. In SketchUp choose **Window → Extension Manager → Install Extension** and select `dist/ZillaFurnitureTools-v0.3.0.rbz`.
3. Select the cabinet assembly or individual panel components. Open the **Extensions** menu (called **Plugins** in the Ruby API).

## Commands

| Menu command | Result |
| --- | --- |
| Drill planner | Detects simple perpendicular board joints, proposes confirmat positions and front-edge candidates, creates guide groups and a review CSV. |
| Smart Joint | Lets you pick a butt seam and manually choose provisional confirmat or dowel positions. |
| Drawer front guides | Places matching through-wall and blind-facade **guides** on a touching drawer front and front wall. Choose two to four fixing positions. |
| Slide guides | Places cabinet-side and drawer-side **guides** across a runner gap. Enter mounting offsets from the *exact* rail drawing separately for each part. |
| Export mounting guides CSV | Writes the drawer-front and slide guide groups as a review sheet marked `GUIDE_ONLY_NOT_VIYAR_IMPORT`. |

The drawer commands search a selected assembly for `Front_Facade`, `Drawer_Front_Wall`, `Left_Side`/`Right_Side` and `Drawer_Left`/`Drawer_Right`. Parts must be separate rectangular SketchUp groups/components, 12–25 mm thick, aligned to model axes. The full assembly can be selected; the automatic cabinet scanner excludes drawer parts unless a drawer command requests them. Concepts, handles, casters and other non-panel objects are skipped.

**All generated circles and construction points are guides. No board is cut or drilled.** The CSV has model-space coordinates for checking and is **not** a Viyar Pro import, CNC program, or proof that a hole pattern matches a fitting. The hardware library marks the manual drawer and slide entries as unverified and guide-only. Confirmat/dowel sizes are also preliminary. Obtain the exact fixing/rail SKU drawing, screw sizes and counterbore instructions before machining.

For the AC Station model and its Viyar/OpenCutList route, see [AC Station workflow](docs/AC_STATION_WORKFLOW_UA.md). In particular, Viyar's drilling service has a 70 mm minimum part width; several 50 mm rails in that model are cuttable but not eligible for its CNC drilling service.

## Development

Run `ruby test/test_planner.rb`, `ruby test/test_hardware.rb`, `ruby test/test_mounting.rb`, then `python tools/build_rbz.py`. GitHub Actions runs the same checks. `test/sketchup_integration_probe.rb` is an optional test for a **saved** AC Station OCL draft scene in a live SketchUp session. It adds one guide group, checks CSV rows and undoes the guide operation. It does not change the saved model.

Roadmap: verified fitting templates, part-local datums and actual hole geometry, per-part DXF/ABF export, and a checked import into Viyar Pro. See [ROADMAP](docs/ROADMAP.md).

MIT license.
