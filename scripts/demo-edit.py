#!/usr/bin/env python3
"""Cuts a demo recording (`--record-demo`'s raw.mov) into a shareable 1920x1080 mp4: keeps the
listed segments, each at its own speed (sound sped up without changing pitch), then applies
eased camera zooms over the result.

    scripts/demo-edit.py out.mp4 --edit edit.json raw.mov [raw2.mov ...]

edit.json:
    {"segments": [[recording, start, end, speed], ...],   (recording: 0 for the first file)
     "keys": [[output time, zoom, centre x, centre y], ...]}

Zoom 1 is the whole recording; centres are in the recording's pixels. Between keyframes the
camera eases (smoothstep); before the first and after the last it holds.
"""
import argparse, json, os, subprocess, sys


def piecewise(keys, index):
    """An ffmpeg expression in t for one keyframe component, eased between keyframes."""
    expr = str(keys[-1][index])
    for (t0, *a), (t1, *b) in reversed(list(zip(keys, keys[1:]))):
        v0, v1 = a[index - 1], b[index - 1]
        if t1 <= t0:
            continue
        p = f"clip((t-{t0})/{t1 - t0},0,1)"
        expr = f"if(lt(t,{t1}),({v0}+({v1 - v0})*{p}*{p}*(3-2*{p})),{expr})"
    return f"if(lt(t,{keys[0][0]}),{keys[0][index]},{expr})"


def tempo(speed):
    """atempo takes 0.5–2 per stage."""
    stages = []
    while speed > 2:
        stages.append("atempo=2"); speed /= 2
    while speed < 0.5:
        stages.append("atempo=0.5"); speed /= 0.5
    stages.append(f"atempo={speed:.4f}")
    return ",".join(stages)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("out"); parser.add_argument("raws", nargs="+")
    parser.add_argument("--edit", required=True)
    parser.add_argument("--size", default="3024x1700", help="the recording's pixel size")
    args = parser.parse_args()
    width, height = map(int, args.size.split("x"))
    edit = json.load(open(args.edit))
    segments, keys = edit["segments"], edit["keys"]
    length = sum((end - start) / speed for _, start, end, speed in segments)

    # Pass 1: the segments, stitched at high quality (filters after a concat see each
    # segment's own clock, so the zooms run in a second pass on the stitched file).
    parts, labels = [], []
    for i, (source, start, end, speed) in enumerate(segments):
        parts.append(f"[{source}:v]trim={start}:{end},setpts=(PTS-STARTPTS)/{speed},fps=60[v{i}]")
        parts.append(f"[{source}:a]atrim={start}:{end},asetpts=PTS-STARTPTS,{tempo(speed)}[a{i}]")
        labels.append(f"[v{i}][a{i}]")
    parts.append(f"{''.join(labels)}concat=n={len(segments)}:v=1:a=1[cv][ca]")
    stitched = args.out + ".stitched.mov"
    inputs = [flag for raw in args.raws for flag in ("-i", raw)]
    subprocess.run(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", ";".join(parts), "-map", "[cv]", "-map", "[ca]",
                    "-c:v", "libx264", "-preset", "fast", "-crf", "10", "-r", "60", "-c:a", "pcm_s16le", stitched], check=True)
    # Pass 2: zooms, one stretch between keyframes at a time (short expressions on each piece's
    # own clock), then joined with the loudness and fades.
    base = max(1920 / width, 1080 / height)
    stops = [k for k in keys if k[0] < length] + [[length, *keys[-1][1:]]]
    pieces = []
    for i, ((t0, z0, x0, y0), (t1, z1, x1, y1)) in enumerate(zip(stops, stops[1:])):
        if t1 - t0 < 0.02:
            continue
        p = f"clip(t/{t1 - t0},0,1)"; e = f"({p}*{p}*(3-2*{p}))"
        z, cx, cy = f"({z0}+({z1 - z0})*{e})", f"({x0}+({x1 - x0})*{e})", f"({y0}+({y1 - y0})*{e})"
        video = (f"scale=w='2*ceil({width}*{base}*{z}/2)':h='2*ceil({height}*{base}*{z}/2)':eval=frame:flags=lanczos,"
                 f"crop=1920:1080:x='clip({cx}*{base}*{z}-960,0,iw-1920)':y='clip({cy}*{base}*{z}-540,0,ih-1080)',format=yuv420p")
        piece = f"{args.out}.piece{i:02d}.mov"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-ss", f"{t0:.4f}", "-t", f"{t1 - t0:.4f}", "-i", stitched, "-an", "-vf", video,
                        "-c:v", "libx264", "-preset", "fast", "-crf", "10", "-r", "60", piece], check=True)
        pieces.append(piece)
    listing = args.out + ".pieces.txt"
    with open(listing, "w") as f:
        f.writelines(f"file '{os.path.abspath(piece)}'\n" for piece in pieces)
    audio = f"volume=11dB,alimiter=limit=0.9:level=false,afade=t=in:d=0.15,afade=t=out:st={length - 0.4:.3f}:d=0.4"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", listing, "-i", stitched,
                    "-map", "0:v", "-map", "1:a", "-af", audio, "-shortest",
                    "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-profile:v", "high", "-r", "60", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", args.out], check=True)
    for piece in pieces: os.remove(piece)
    os.remove(listing)
    os.remove(stitched)
    duration = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", args.out],
                                    capture_output=True, text=True, check=True).stdout)
    print(f"{args.out}: {duration:.2f} s (planned {length:.2f} s)")


if __name__ == "__main__":
    main()
