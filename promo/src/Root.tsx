import { Composition } from "remotion";
import { Promo } from "./Promo";
import { cutFrames } from "./Cut";

// "Film": the full minute, for the website and YouTube. "Short": the 38-second cut for social posts.
export const RemotionRoot = () => (
  <>
    <Composition id="Film" component={Promo} defaultProps={{ cut: "film" as const }} durationInFrames={cutFrames("film")} fps={30} width={1920} height={1080} />
    <Composition id="Short" component={Promo} defaultProps={{ cut: "short" as const }} durationInFrames={cutFrames("short")} fps={30} width={1920} height={1080} />
  </>
);
