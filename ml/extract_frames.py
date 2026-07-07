import argparse
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video", help="Input video path")
    parser.add_argument("--fps", type=float, default=2.0, help="Frames per second to extract")
    parser.add_argument("--out", default="dataset/images", help="Output image directory")
    args = parser.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_pattern = str(out_dir / "frame_%06d.jpg")

    cmd = [
        "ffmpeg", "-y",
        "-i", args.video,
        "-vf", f"fps={args.fps}",
        out_pattern,
    ]
    subprocess.run(cmd, check=True)
    print("Frames written to", out_dir)


if __name__ == "__main__":
    main()
