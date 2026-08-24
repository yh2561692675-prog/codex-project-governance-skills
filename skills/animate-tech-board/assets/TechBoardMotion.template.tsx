import React from "react";
import {
  AbsoluteFill,
  Composition,
  Easing,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const SOURCE_WIDTH = 1920;
const SOURCE_HEIGHT = 1080;
const OUT_WIDTH = 2560;
const OUT_HEIGHT = 1440;
const ASSET = "reference.png";

type Slice = {
  x: number;
  y: number;
  width: number;
  height: number;
  start: number;
  duration?: number;
  drift?: number;
};

// Replace with complete badge, title, and module bounds measured on the source.
const SLICE_CONFIG: Slice[] = [
  {x: 64, y: 44, width: 360, height: 90, start: 6},
  {x: 90, y: 140, width: 1100, height: 120, start: 20},
  {x: 70, y: 300, width: 330, height: 650, start: 50},
];

const ease = Easing.bezier(0.16, 1, 0.3, 1);

const SourceSlice: React.FC<Slice> = ({
  x,
  y,
  width,
  height,
  start,
  duration = 62,
  drift = 36,
}) => {
  const frame = useCurrentFrame();
  const sx = OUT_WIDTH / SOURCE_WIDTH;
  const sy = OUT_HEIGHT / SOURCE_HEIGHT;
  const end = start + duration;

  return (
    <div
      style={{
        position: "absolute",
        left: x * sx,
        top: y * sy,
        width: width * sx,
        height: height * sy,
        overflow: "hidden",
        mixBlendMode: "screen",
        opacity: interpolate(frame, [start, end - 10], [0, 1], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: ease,
        }),
        translate: `${interpolate(frame, [start, end], [drift, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: ease,
        })}px 0px`,
      }}
    >
      <Img
        src={staticFile(ASSET)}
        style={{
          position: "absolute",
          left: -x * sx,
          top: -y * sy,
          width: OUT_WIDTH,
          height: OUT_HEIGHT,
        }}
      />
    </div>
  );
};

const PerspectiveGrid: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const horizon = OUT_HEIGHT * 0.71;
  const centerX = OUT_WIDTH / 2;
  const phase = (frame / durationInFrames) * 2.15;
  const pulse = 0.78 + Math.sin((frame / 30) * Math.PI * 0.55) * 0.12;

  return (
    <AbsoluteFill>
      <svg width={OUT_WIDTH} height={OUT_HEIGHT} style={{filter: "drop-shadow(0 0 9px rgba(0,191,255,.72))"}}>
        {Array.from({length: 25}, (_, i) => {
          const t = (i - 12) / 12;
          return (
            <line
              key={`ray-${i}`}
              x1={centerX + t * 55}
              y1={horizon}
              x2={centerX + t * 1760}
              y2={OUT_HEIGHT + 40}
              stroke={`rgba(0,181,255,${0.24 * pulse})`}
              strokeWidth={1.2}
            />
          );
        })}
        {Array.from({length: 16}, (_, i) => {
          const p = ((i / 16 + phase) % 1 + 1) % 1;
          const depth = Math.pow(p, 2.25);
          const y = horizon + depth * (OUT_HEIGHT - horizon + 60);
          const halfWidth = 78 + depth * 1510;
          return (
            <line
              key={`cross-${i}`}
              x1={centerX - halfWidth}
              x2={centerX + halfWidth}
              y1={y}
              y2={y}
              stroke={`rgba(18,174,255,${p * pulse * 0.85})`}
              strokeWidth={0.8 + depth * 2.4}
            />
          );
        })}
      </svg>
    </AbsoluteFill>
  );
};

export const TechBoardMotion: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();

  return (
    <AbsoluteFill style={{backgroundColor: "#01060d", overflow: "hidden"}}>
      <AbsoluteFill
        style={{
          scale: interpolate(frame, [0, durationInFrames - 1], [1.008, 1.016], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
        }}
      >
        <AbsoluteFill
          style={{
            background:
              "radial-gradient(ellipse at 50% 72%, rgba(7,39,76,.3) 0%, rgba(1,12,27,.16) 34%, transparent 67%), linear-gradient(180deg,#01060d 0%,#010813 58%,#020b19 100%)",
          }}
        />
        <div
          style={{
            position: "absolute",
            left: OUT_WIDTH * 0.25,
            top: OUT_HEIGHT * 0.6,
            width: OUT_WIDTH * 0.5,
            height: OUT_HEIGHT * 0.2,
            borderRadius: "50%",
            background: "radial-gradient(ellipse,rgba(90,210,255,.4),rgba(10,92,190,.18) 35%,transparent 72%)",
            filter: "blur(38px)",
            opacity: 0.28 + Math.sin((frame / 30) * Math.PI * 0.4) * 0.05,
          }}
        />
        <PerspectiveGrid />
        {SLICE_CONFIG.map((slice, index) => <SourceSlice key={index} {...slice} />)}
        <AbsoluteFill
          style={{
            background: "radial-gradient(ellipse at 50% 47%,transparent 42%,rgba(0,2,8,.38) 82%,rgba(0,0,0,.72) 100%)",
          }}
        />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const TechBoardComposition = () => (
  <Composition
    id="TechBoardMotion"
    component={TechBoardMotion}
    durationInFrames={270}
    fps={30}
    width={OUT_WIDTH}
    height={OUT_HEIGHT}
  />
);
