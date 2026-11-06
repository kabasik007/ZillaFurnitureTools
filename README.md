# Zilla Furniture Tools

SketchUp extension for sheet-material joints, OpenCutList edge materials and drilling. Current version: **0.7.1**.

Version 0.7.0 adds two Viyar package commands. **Пакет CSV для розкрою Viyar** exports the parts and edge CSV, drilling and hardware review sheets, and a material manifest without requiring ABF. **Пакет DXF з ABF-розкладки** additionally exports an existing `ABF_Flatten` layout with the same flatten-only AutoCAD 2007 options as Viyar's `dxf2viyarpro_v1.0.9` extension. The latter blocks missing flatten, missing physical holes, and technical review scenes. **ABF must create the flatten first; Zilla does not convert its own 3D DXF into a Viyar manufacturing project.** The drilling and hardware CSVs are review sheets, not Viyar import files. Verify every accepted operation in a test ViyarPro import before ordering.

A live CSV package from the selected AC Station model is at [AC Station test package](../../AC-Station/exports/viyar_csv_package_20261106/manifest.json): 15 edged parts, 42 recorded physical holes, and two hardware entries. The caster article is still missing; the slide article and mounting must be checked against its supplier drawing. Only `01_parts_edges_viyar.csv` is an import candidate. Material codes live in `manifest.json` because Viyar's parts CSV import uses material selection in the receiving project.

Version 0.7.1 adds one `05_batch_face_drilling_TRIAL.dxf` to the CSV package. It contains all selected board contours and face-hole circles in one millimetre DXF for a **separate test project**. The current AC Station v6 file contains 15 contours, 30 face holes (14 through on `DEPTHF`, 16 blind on a review layer), and 12 edge holes listed only in the drilling CSV. Viyar's depth and edge-hole interpretation of this trial DXF is unverified. The selected material in the user's first Viyar import screenshot was Kronospan 8622, while the AC Station specification calls for alder 1912 BS, Viyar code 49004.

The revised AC Station package is [v6 CSV and trial DXF](../../AC-Station/exports/viyar_csv_package_v6_20261106/manifest.json). Three top stops were increased from 52 to 54 mm finished height; their saw width is now 52 mm, giving 50 mm after the selected top-edge allowance. The 50 mm concealed upper rails remain unchanged because making them 70 mm would interfere with the drawer. This revision has not been accepted in a ViyarPro test import.

Version 0.6.1 adds an instance-aware part inventory for CSV and drilling review. Repeated names, nested copies and arbitrary rotation now preserve each instance's local board dimensions in those exports. The joint planner remains limited to panels aligned with model axes; it refuses other orientations until a local-frame joint engine is validated. See [initial GAVA/Zilla audit](docs/INITIAL_AUDIT_GAVA_UA.md) and [Viyar format research](docs/VIYAR_FORMAT_RESEARCH.md).

Open **Extensions → Zilla Furniture Tools → Панель інструментів**, or click **Z** on the visible Zilla toolbar. One Ukrainian panel brings together perspective/X-Ray, technical scenes, manual joints, drawer corners, edge banding and exports. The toolbar also has shortcuts **+** (joint), **4** (drawer corners), **X** (X-Ray).

The three technical scenes live in `AC_Station_v5_TECHNICAL_REVIEW.skp`; the older v4 model does not contain them. Blue cylinders show hole axes, green means 2 mm edge band, red means nominal 0.5 mm. Use the clean `AC_Station_v5_drawer_joints_TEST.skp` for geometry export.

The new CSV export writes 15 assigned AC Station LDSP panels in the Viyar text-import column order, without a header, using semicolons and UTF-8 BOM. It subtracts assigned nominal edge thickness from finished local dimensions. Plywood, holes and 3D coordinates are separate. The native 3D DXF preserves assembly geometry in millimeters; hidden instances, reference objects and generated guides are temporarily excluded and the model is restored. **It is not an ABF manufacturing export.** Recorded drilled rectangular panels can now be selected for joint planning after solid/volume checks; already-cut hole positions are rejected instead of creating duplicate guides.

## Install

1. Run `python tools/build_rbz.py` from this repository.
2. In SketchUp choose **Window → Extension Manager → Install Extension** and select `dist/ZillaFurnitureTools-v0.7.1.rbz`. Restart SketchUp after upgrading to replace the old separate menu entries.

`Drawer box: 4 corner joints` plans all four joints of the named 18 mm drawer walls: normally 8 confirmats / 16 holes. Select the drawer assembly first. The bottom, facade and runners are separate connections. Smart Joint now also scans drawer components for manual joint placement. These remain provisional drilling profiles, not validated Viyar CNC programs.
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
