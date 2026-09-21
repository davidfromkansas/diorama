"""Build an isolated native UI harness; availability/login are simulated, credentials untouched.
Open the printed app with the computer-use tool or Finder to exercise the matrix.
"""
from pathlib import Path
import subprocess, plistlib
root = Path(__file__).resolve().parents[1]
build = Path('/tmp/diorama-projects-build')
work = Path('/tmp/diorama-onboarding-harness')
work.mkdir(exist_ok=True)
subprocess.run(['swift', 'build', '--scratch-path', str(build)], cwd=root, check=True)
(work/'Main.swift').write_text((root/'scripts/onboarding-ui/Main.swift').read_text())
(work/'AgentSettingsView.swift').write_text((root/'Sources/DioramaApp/AgentSettingsView.swift').read_text())
s = (root/'Sources/DioramaApp/ExecutionViews.swift').read_text()
(work/'ExecutionModelPicker.swift').write_text(s[:s.index('struct NewExecutionTaskView:')])
app=Path('/tmp/DioramaOnboardingVerification.app')
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
subprocess.run(['swiftc','-parse-as-library','-swift-version','6','-default-isolation','MainActor','-I',str(build/'debug/Modules'),*[str(p) for p in work.glob('*.swift')],*[str(p) for p in (build/'debug/DioramaCore.build').glob('*.swift.o')],'-o',str(app/'Contents/MacOS/DioramaOnboardingVerification')],check=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'DioramaOnboardingVerification','CFBundleIdentifier':'local.diorama.onboarding-verification','CFBundleName':'Diorama Onboarding Verification','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0'}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
