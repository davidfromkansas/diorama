"""Build isolated native permission UI, using the production card and presenter."""
from pathlib import Path
import subprocess, plistlib
root = Path(__file__).resolve().parents[1]
build = Path('/tmp/diorama-projects-build')
app = Path('/tmp/DioramaPermissionVerification.app')
(app/'Contents/MacOS').mkdir(parents=True, exist_ok=True)
subprocess.run(['swiftc','-parse-as-library','-swift-version','6','-default-isolation','MainActor','-I',str(build/'debug/Modules'),str(root/'scripts/permission-ui/Main.swift'),str(root/'Sources/DioramaApp/PermissionReviewCard.swift'),*[str(p) for p in (build/'debug/DioramaCore.build').glob('*.swift.o')],'-o',str(app/'Contents/MacOS/PermissionVerification')],check=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'PermissionVerification','CFBundleIdentifier':'local.diorama.permission-verification','CFBundleName':'Permission Verification','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0'}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
