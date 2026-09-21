from pathlib import Path
import subprocess, plistlib
root = Path(__file__).resolve().parents[1]
build = Path('/tmp/diorama-projects-build')
app = Path('/tmp/DioramaReviewVerification.app')
(app/'Contents/MacOS').mkdir(parents=True, exist_ok=True)
subprocess.run(['swiftc','-parse-as-library','-swift-version','6','-default-isolation','MainActor','-I',str(build/'debug/Modules'),str(root/'scripts/review-ui/Main.swift'),str(root/'Sources/DioramaApp/SessionChangesView.swift'),*[str(p) for p in (build/'debug/DioramaCore.build').glob('*.swift.o')],'-o',str(app/'Contents/MacOS/ReviewVerification')],check=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'ReviewVerification','CFBundleIdentifier':'local.diorama.review-verification','CFBundleName':'Review Verification','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0'}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
