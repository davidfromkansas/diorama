"""One contact sheet per clip (rows = views, columns = sampled frames): sheets.py <render_dir>"""
import sys, os, re, glob, subprocess
d = sys.argv[1]
mont = os.path.join(os.path.dirname(__file__), "montage.py")
clips = sorted({re.sub(r"_\d{3}_[a-z]+\.png$", "", os.path.basename(f)) for f in glob.glob(os.path.join(d, "*_[0-9][0-9][0-9]_*.png"))})
for c in clips:
    files = []
    for v in ("front", "side", "production"):
        files += sorted(glob.glob(os.path.join(d, f"{c}_[0-9][0-9][0-9]_{v}.png")))
    n = len(glob.glob(os.path.join(d, f"{c}_[0-9][0-9][0-9]_front.png")))
    subprocess.run([sys.executable, mont, os.path.join(d, f"sheet_{c}.png"), str(n), *files], check=True)
