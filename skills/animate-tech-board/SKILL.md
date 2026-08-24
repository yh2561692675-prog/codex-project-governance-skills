---
name: animate-tech-board
description: Turn a static technology information board, dashboard poster, infographic, course slide, or card-based reference image into a polished Remotion video with clean whole-module entrances, a forward-flowing perspective grid, breathing neon glow, center fog, and restrained camera depth. Use for 16:9 sci-fi or electronic-information motion graphics when the source layout must stay recognizable and no text, card, icon, crop edge, ghost image, or background residue may appear before its intended entrance.
---

# Animate Tech Board

Build a clean motion version of a static information board while preserving its original typography and layout. Prefer image slicing plus synthetic depth effects over recreating dense text manually.

## Workflow

1. Inspect the reference image at original resolution.
2. Read the available Remotion best-practices skill before writing Remotion code.
3. Reuse an existing Remotion project or scaffold a blank one. Put local media in `public/` and load it with `staticFile()` and `<Img>`.
4. Decide the composition settings from the request. Default to 2560x1440, 30 fps, and 270 frames when the user requests a 9-second 16:9 video.
5. Define rectangular slices for the badge, title, and each complete module. Scale source coordinates independently on X and Y.
6. Build the atmosphere synthetically: dark gradient, deterministic SVG perspective grid, center fog, glow breathing, and optional circuit sparks.
7. Animate each slice as one complete unit using frame-driven opacity and slight translation. Use a short stagger for related modules.
8. Render and inspect frame 0, a mid-entrance frame, and a settled frame before rendering the final MP4.

Use [assets/TechBoardMotion.template.tsx](assets/TechBoardMotion.template.tsx) as the starting component. Replace `SOURCE_WIDTH`, `SOURCE_HEIGHT`, `SLICE_CONFIG`, and the asset filename.

## Clean Layer Rules

- Never place the full reference image behind the scene at low opacity. It produces ghost text and module residue.
- Never use a bottom crop that overlaps any card or text. Keep only a verified clean strip, or omit the source background and generate the floor synthetically.
- Crop every module as a complete rectangle including its icon, border, heading, and body.
- Reveal whole modules with opacity and translation. Do not use a hard horizontal clip that exposes half a word, icon, or card unless the user explicitly requests a wipe.
- Apply `mixBlendMode: "screen"` to slices when black crop rectangles or seams remain visible. Confirm that the card fill still has enough contrast.
- Keep the first frame free of every content slice. A grid, fog, or clean decorative bottom strip may remain.
- Drive every animation from `useCurrentFrame()`; do not use CSS transitions or CSS animations.

## Motion Direction

- Move the floor toward the camera by advancing horizontal grid lines through nonlinear perspective depth.
- Keep vertical rays fixed on the vanishing point.
- Use only a 0.5-1.5% camera-scale drift across the whole shot.
- Modulate glow and fog with slow sine waves. Keep the breathing subtle.
- Let the badge and title enter first, followed by modules with a 4-8 frame stagger.
- Hold the completed layout long enough to read it.

## Validation

Read [references/quality-checklist.md](references/quality-checklist.md) before the final render.

Run the project lint/type check, then render representative frames:

```powershell
npm run lint
npx remotion still <composition-id> renders/opening-clean.png --frame=0
npx remotion still <composition-id> renders/entrance-clean.png --frame=82
npx remotion still <composition-id> renders/settled.png --frame=150
```

Render H.264 after all three frames pass visual inspection:

```powershell
npx remotion render <composition-id> renders/final.mp4 --codec=h264 --crf=16 --pixel-format=yuv420p
```

Verify width, height, frame rate, and duration with Remotion FFprobe when the final specification matters.
