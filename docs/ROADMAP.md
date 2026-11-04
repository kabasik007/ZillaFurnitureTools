# Zilla Furniture Tools — Roadmap

Updated: 2026-11-04. Planning document: do not treat listed features as implemented. Initial confirmat planner lives in draft PR #1 and still needs on-device SketchUp verification.

## Product mission

A UA/EN SketchUp extension for cabinet construction: hover perpendicular board joint -> choose fastener -> preview accurate drilling in both boards -> approve positions -> create reversible guides (later physical holes) -> apply edge-banding -> export shop drawings. Existing models should work without remodeling.

## Milestone P0: interactive Smart Joint (#6)

1. Activate a dedicated SketchUp tool with custom cursor. Move pointer across furniture and highlight viable 90-degree face-to-edge contacts (never infer joinability solely from 90 degrees).
2. Click one highlighted seam. Show the exact two components, thickness, contact length and a fittings selector with hardware thumbnails.
3. Offer only geometrically compatible options, including Confirmat 7x50, Confirmat+Dowel, Dowel+Glue, Minifix/Rastex+Dowel and Permo+Dowel with a verified SKU profile.
4. Preview in translucent overlay: face hole, mating edge hole, Ø, depth, centers, distances to edges, and side/axis labels. Slider/numeric values for along-seam position, quantity and symmetry.
5. Click to commit guides; Escape cancels; Undo reverts. Separate explicit confirmation is required for physical hole creation.
6. Handle grouped/nested/rotated component instances, mirrored furniture and incomplete joints; cache candidates for mouse-move performance.
7. Detect and block through-breakout, overlap with other fasteners, drawer slides, minimum wall thickness, ambiguous mirrored references and unsupported hardware.

SketchUp APIs: https://ruby.sketchup.com/Sketchup/Tool.html ; https://ruby.sketchup.com/Sketchup/PickHelper.html ; https://ruby.sketchup.com/Sketchup/InputPoint.html

## Milestone P0: data-driven fastener catalog (#7)

Store hardware profiles with manufacturer, SKU, datasheet URL/revision, compatible thickness/materials, hole operations (face/edge), precise diameters/depths/countersinks/axes, layout offsets, fastener quantity, and verified/draft status. Thumbnail/tech-drawing references should link to official material; do not reproduce copyrighted supplier image files without permission.

Typical profiles:
- Confirmat 7x50 for cabinet butt joints.
- Wooden dowels Ø6 and Ø8 with glue; corresponding aligned blind holes.
- Confirmat + dowel; Minifix/Rastex + dowel; Permo + dowel.
- Drawer front: permanent glued dowels, screws from inside with controlled length, removable/adjustable front bracket (by SKU).
- Side telescopic ball-bearing runners, 45 mm class; separate concealed under-mount runner profiles.
- Wheel caster mounting plates / adjustable feet by exact SKU (otherwise guide-only).

ViyarPro already allows changing Confirmat+Dowel, Minifix+Dowel, Permo+Dowel and telescopic vs concealed drawers: https://viyar.ua/ua/news/novi_dizayni_kukhon_i_onovleniy_interfeys_viyarpro_mebli/

## Milestone P1: drawer box + facade joinery (#3)

Select drawer box and decorative front separately. Offer user choices: fixed with glued dowels, inside-mounted screws, or adjustable/removable attachment from a selected manufacturer profile. Show 3D matching-hole preview, reference faces, drawer reveal and facade overlap; warn about drilling through front surfaces. Preserve handles and drawer rails.

## Milestone P1: slide rail and furniture foot drilling (#5)

- Side-mounted telescopic rail: select brand/SKU, length, height, side, mounting position, exact cabinet and drawer hole patterns and correct clearance. An illustrative Viyar article quotes 13 mm per side for its example only; never assume universal. https://viyar.ua/ua/articles/kak_ustanovit_teleskopicheskie_napravlyayushchie_/
- Under-mount slides: independent hardware-specific rail/locking device/rear hook layout; see https://www.blum.com/ua/uk/products/runnersystems/tandem/downloads-videos/
- Feet/casters: only drill if chosen hardware's plate or insert dimensions are verified. Otherwise manual centers or no drills.

## Milestone P2: machining, exports and edge-banding (#2, #4)

- Explicitly approved physical blind or through bores. All operations in local panel coordinates, world-to-instance transform safety, shared component definition protection and full Undo.
- Generate per-part drilling CSV, DXF, part IDs, depth/diameter, machine-side labels, drawing PDF and BOM.
- Distinguish edge/face and blind/through holes as ViyarPro documentation does. https://www.viyar.pro/service/doc/?cid=dsp&s=drilling
- Mark exposed edges for PVC 0.4/1/2 mm as examples only, respecting selected material, part finished dimensions, texture direction, manual overrides. Integrate or cross-check OpenCutList: https://docs.opencutlist.org/
- Investigate ViyarPro SketchUp/DXF/CSV import as supported by its official introduction: https://viyar.ua/articles/viyarpro-mebli-innovatsiyniy-onlayn-konstruktor-dlya-vashoi-roboti/
- The user must verify vendor/production compatibility; data export is not a guarantee of machine-readiness.

## Acceptance checklist

- On an existing SKP cabinet: locate and approve a correct joint with mouse, no geometry modification in preview, display 2-sided bore placements accurately, undo after applying.
- Select a dowel/glue drawer facade method and side runner model; correct independent positions on both matching members.
- Block incomplete/unverified profiles rather than generating invented drill patterns.
- Test parts against manufacturer's dimensions and manufacturing preview; Ruby unit tests plus on-device SketchUp integration and reversible model edit test.

Related GitHub issues: #2, #3, #4, #5, #6, #7. Draft PR: #1.

## Existing products / UX to benchmark

- **ViyarPro:** select fastener and automatically compute drill diameters/depths; imports SketchUp and supports DXF/CSV workflows. Source: https://viyar.ua/articles/viyarpro-mebli-innovatsiyniy-onlayn-konstruktor-dlya-vashoi-roboti/ and https://viyar.ua/ua/articles/chto_takoe_prisadka/
- **BAZIS Mebelshchik:** built-in automatic fastener assignment at an individual butt joint or across a panel, including cabinet and drawer slide holes. UX reference: https://bazis-center.ru/system/mebelschik ; full user guide chapter 29 on fastener layout.
- **Blum Cabinet Configurator:** browser-based hardware catalog, collision check, CAD and BXF manufacturing data and drilling positions. Product-specific inspiration for verified profiles. https://www.blum.com/eu/en/services/planning-construction-product-selection/cabinet-configurator/
- **PolyBoard:** parametric hardware libraries, cabinet drilling/groove tooling map and CNC output. https://boole.eu/polyboard.php

Copy *concepts and verified dimensional specifications*, not proprietary code, illustrations, licensed CAD libraries or vendor branding. For each manufacturer picture show official catalog links/thumbnails only where permission is confirmed.
