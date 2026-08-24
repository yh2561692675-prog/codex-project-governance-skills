# Quality checklist

## Opening frame

- No title, card, icon, paragraph, border, or cropped black rectangle is visible.
- The grid and fog are centered on the same vanishing point.
- A retained source-image strip contains only verified decorative pixels.

## Entrance frame

- Every visible module has a complete outline and complete text shapes.
- No hard vertical crop edge crosses a word or icon.
- Later modules may be dimmer, but their visible geometry remains whole.
- Image-slice backgrounds blend into the scene without rectangular seams.
- Grid lines do not overpower body text.

## Settled frame

- All source content is present and matches the reference layout.
- Slice boundaries do not create gaps, doubled borders, or clipped glows.
- Headline and cards are readable at normal video-viewing size.
- The floor moves continuously toward the camera without a visible loop jump.
- Glow and fog breathing remain subtle.

## Technical output

- Composition dimensions, fps, and duration match the request.
- Animations depend only on the Remotion frame.
- Lint and TypeScript checks pass.
- H.264 output is compatible `yuv420p` or the encoder's equivalent 4:2:0 format.
