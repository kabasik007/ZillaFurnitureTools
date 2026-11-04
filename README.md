# Zilla Furniture Tools

SketchUp extension for sheet-material joints, OpenCutList edge materials and drilling. Current version: **0.4.1**.

## Install

1. Run `python tools/build_rbz.py` from this repository.
2. In SketchUp choose **Window → Extension Manager → Install Extension** and select `dist/ZillaFurnitureTools-v0.4.1.rbz`.
3. Select the cabinet assembly or individual panel components. Open the **Extensions** menu (called **Plugins** in the Ruby API).

## Commands

| Menu command | Result |
| --- | --- |
| Drill planner | Detects simple perpendicular board joints, proposes confirmat positions and front-edge candidates, creates guide groups and a review CSV. |
| Smart Joint | Lets you pick a butt seam and manually choose provisional confirmat or dowel positions. |
| Drawer front guides | Places matching through-wall and blind-facade **guides** on a touching drawer front and front wall. Choose two to four fixing positions. |
| Slide guides | Places cabinet-side and drawer-side **guides** across a runner gap. Enter mounting offsets from the *exact* rail drawing separately for each part. |
| Export mounting guides CSV | Writes the drawer-front and slide guide groups as a review sheet marked `GUIDE_ONLY_NOT_VIYAR_IMPORT`. |
| Apply OpenCutList edge plan CSV | Paints four narrow faces of each selected board with nominal 0.5 or 2 mm edge materials from a checked edge-plan CSV. Verify the resulting saw sizes in OpenCutList. |
| Drill selected guides in new SKP | Saves the current scene to a new `.skp`, cuts the selected guide holes as real cylindrical geometry, hides the guide groups, and saves the test copy. |

The drawer commands search a selected assembly for `Front_Facade`, `Drawer_Front_Wall`, `Left_Side`/`Right_Side` and `Drawer_Left`/`Drawer_Right`. Parts must be separate rectangular SketchUp groups/components, 12–25 mm thick, aligned to model axes. The full assembly can be selected; the automatic cabinet scanner excludes drawer parts unless a drawer command requests them. Concepts, handles, casters and other non-panel objects are skipped.

Guide creation alone does not modify the board. **Drill selected guides in new SKP** is a separate, explicit operation that makes true holes in a new SketchUp file; it verifies removed volume and a closed solid after each cut. The guide CSV has model-space coordinates for checking and is **not** a Viyar Pro import, CNC program, or proof that a hole pattern matches a fitting. The hardware library marks the drawer and slide profiles as unverified. Confirmat/dowel sizes are also preliminary. Obtain the exact fixing/rail SKU drawing, screw sizes and counterbore instructions before manufacturing.

For the AC Station model and its Viyar/OpenCutList route, see [AC Station workflow](docs/AC_STATION_WORKFLOW_UA.md). The `tools/build_ac_station_test.rb` script produced a separate test scene with 15 edge-banded boards and 26 physical holes; `tools/export_ac_station_dxf.py` produced inspection drawings. In particular, Viyar's drilling service has a 70 mm minimum part width; the 50 mm rails in that model are cuttable but not eligible for its CNC drilling service.

## Development

Run `ruby test/test_planner.rb`, `ruby test/test_hardware.rb`, `ruby test/test_mounting.rb`, then `python tools/build_rbz.py`. GitHub Actions runs the same checks. `test/sketchup_integration_probe.rb` is an optional test for a **saved** AC Station OCL draft scene in a live SketchUp session. `test/verify_ac_test_model.rb` audits the test scene after drilling.

Roadmap: verified fitting templates and part-local datums, a validated ABF/Viyar DXF interchange, and a trial import with accepted operations in Viyar Pro. The current per-part DXFs are technical drawings for inspection. See [ROADMAP](docs/ROADMAP.md).

MIT license.
