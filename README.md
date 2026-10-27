# RZ/G3L Fast Boot and Seamless Logo

Boot-experience solutions for the RZ/G3L SMARC EVK, BSP v1.0.0 (Yocto
scarthgap). Each one is a set of Yocto layers added to the standard BSP build.
The guide in `docs/` describes how to build, write and customize them.

| Solution | Components | What it does |
|---|---|---|
| 1. Fast Boot + Seamless Still Logo | `meta-rzg3l-fast-boot` + `meta-rzg3l-seamless-logo-still` | Boot to Weston in about 6.8 s instead of 22 s (eMMC boot), with one still logo from U-Boot until Weston |
| 2. Seamless Logo Sequence | `meta-rzg3l-seamless-logo-sequence` + `rzg3l-seamless-logo-sequence-app` | A configurable frame sequence in U-Boot, continued by a Linux application until Weston |
| 3. Seamless Logo CM33 Animation | `meta-rzg3l-seamless-logo-cm33-anim` + `meta-rzg3l-seamless-logo-still` | Under development, not included yet: the CM33 animates a layer over the still logo |

Layer compatibility:

- `meta-rzg3l-fast-boot` does not touch the display path and can be combined
  with any logo layer. Tested with `meta-rzg3l-seamless-logo-still`.
- `meta-rzg3l-seamless-logo-still` and `meta-rzg3l-seamless-logo-sequence`
  cannot be used together. The build stops with an error if both are present.

| Directory | Content |
|---|---|
| `docs/` | `RZG3L-Fast-Boot-Seamless-Logo-Guide.md` (and `.pdf`) |
| `layers/` | Yocto layers, each with a `README` |
| `apps/` | `rzg3l-seamless-logo-sequence-app`, the sample application of Solution 2 |
| `image/` | Prebuilt WIC images of Solutions 1 and 2 |
| `reference/` | RZ/G3L Linux Start-up Guide |
| `tools/` | `md2pdf.py`: renders the guide as PDF |
