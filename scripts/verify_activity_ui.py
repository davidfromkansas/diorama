"""Build isolated native activity panel. No agent execution or user storage writes."""
from pathlib import Path
import subprocess, plistlib
root = Path(__file__).resolve().parents[1]
build = root / '.build/debug'
app = Path('/tmp/DioramaActivityVerification.app')
(app/'Contents/MacOS').mkdir(parents=True, exist_ok=True)
subprocess.run(['swiftc','-parse-as-library','-swift-version','6','-default-isolation','MainActor','-I',str(build/'Modules'),str(root/'scripts/activity-ui/Main.swift'),str(root/'Sources/DioramaApp/SessionActivityPanel.swift'),*[str(p) for p in (build/'DioramaCore.build').glob('*.swift.o')],'-o',str(app/'Contents/MacOS/ActivityVerification')],check=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'ActivityVerification','CFBundleIdentifier':'local.diorama.activity-verification','CFBundleName':'Activity Verification','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0'}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
