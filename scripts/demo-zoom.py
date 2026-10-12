#!/usr/bin/env python3
"""Turns the demo recording (`--record-demo`'s raw.mov) into a shareable 1920x1080 mp4 with
smooth camera zooms.

    scripts/demo-zoom.py raw.mov out.mp4 --start 0.35 --length 12.9 --keys keys.json

keys.json lists keyframes, each [time, zoom, centre x, centre y]: time in output seconds, zoom
1 = the whole recording, the centre in the recording's pixels. Between keyframes the camera eases
(smoothstep); before the first and after the last it holds.
"""
import argparse, json, subprocess, sys


def piecewise(keys, index):
    """An ffmpeg expression in t for one keyframe component, eased between keyframes."""
    expr = str(keys[-1][index])
    for (t0, *a), (t1, *b) in reversed(list(zip(keys, keys[1:]))):
        v0, v1 = a[index - 1], b[index - 1]
        if t1 <= t0:
            continue
        p = f"clip((t-{t0})/{t1 - t0},0,1)"
        eased = f"({v0}+({v1 - v0})*{p}*{p}*(3-2*{p}))"
        expr = f"if(lt(t,{t1}),{eased},{expr})"
    return f"if(lt(t,{keys[0][0]}),{keys[0][index]},{expr})"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("raw"); parser.add_argument("out")
    parser.add_argument("--start", type=float, default=0); parser.add_argument("--length", type=float, required=True)
    parser.add_argument("--keys", required=True)
    parser.add_argument("--size", default="3024x1700", help="the recording's pixel size")
    args = parser.parse_args()
    width, height = map(int, args.size.split("x"))
    keys = json.load(open(args.keys))
    zoom, cx, cy = piecewise(keys, 1), piecewise(keys, 2), piecewise(keys, 3)
    base = max(1920 / width, 1080 / height)
    # Scale the whole frame so the zoomed region is 1920 wide, then cut 1920x1080 around the centre.
    scale = f"scale=w='2*ceil({width}*{base}*({zoom})/2)':h='2*ceil({height}*{base}*({zoom})/2)':eval=frame:flags=lanczos"
    crop = (f"crop=1920:1080:x='clip(({cx})*{base}*({zoom})-960,0,iw-1920)':"
            f"y='clip(({cy})*{base}*({zoom})-540,0,ih-1080)'")
    command = ["ffmpeg", "-y", "-v", "error", "-ss", str(args.start), "-t", str(args.length), "-i", args.raw,
               "-vf", f"setpts=PTS-STARTPTS,{scale},{crop},fps=60,format=yuv420p",
               "-af", "asetpts=PTS-STARTPTS,volume=10dB,alimiter=limit=0.9:level=false,afade=t=out:st=" + str(args.length - 0.35) + ":d=0.35",
               "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-profile:v", "high",
               "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", args.out]
    subprocess.run(command, check=True)
    duration = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", args.out],
                                    capture_output=True, text=True, check=True).stdout)
    print(f"{args.out}: {duration:.2f} s")
    if duration > args.length + 0.05:
        sys.exit("longer than asked")


if __name__ == "__main__":
    main()
