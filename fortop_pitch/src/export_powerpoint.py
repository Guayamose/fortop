"""Export the current deck with the locally installed Windows PowerPoint.

Keeps existing PowerPoint sessions open. The temporary deck is opened read-only,
without a window. qpdf extracts slide PDFs with their hyperlink annotations.
"""

import base64
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"


def windows_path(path):
    return subprocess.check_output(["wslpath", "-w", str(path)], text=True).strip()


def main():
    slugs = [file.stem for file in sorted((ROOT / "slides").glob("*.svg"))]
    if not slugs or any(not re.fullmatch(r"\d{2}-[a-z-]+", slug) for slug in slugs):
        raise ValueError("Slide names must be numbered Spanish slugs.")
    config = {"source": windows_path(ROOT / "Fortop-Pitch.pptx"),
              "output": windows_path(ROOT), "slugs": slugs}
    payload = base64.b64encode(json.dumps(config).encode()).decode()
    script = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$pitchConfig = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CONFIG__')) | ConvertFrom-Json
$pitchWork = Join-Path $env:TEMP 'fortop-pitch-native-render'
New-Item -ItemType Directory -Force -Path $pitchWork | Out-Null
$pitchFile = Join-Path $pitchWork 'Fortop-Pitch.pptx'
Copy-Item -LiteralPath $pitchConfig.source -Destination $pitchFile -Force
$pitchExisting = $true
$pitchPresentation = $null
try {
  try { $pitchApp = [Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application') }
  catch { $pitchExisting = $false; $pitchApp = New-Object -ComObject PowerPoint.Application }
  $pitchPresentation = $pitchApp.Presentations.Open($pitchFile, $true, $false, $false)
  if ($pitchPresentation.Slides.Count -ne $pitchConfig.slugs.Count) { throw 'Slide count differs from SVG sources.' }
  for ($pitchIndex = 1; $pitchIndex -le $pitchPresentation.Slides.Count; $pitchIndex++) {
    $pitchName = $pitchConfig.slugs[$pitchIndex - 1] + '.png'
    $pitchPNG = Join-Path $pitchWork $pitchName
    $pitchPresentation.Slides.Item($pitchIndex).Export($pitchPNG, 'PNG', 1920, 1080)
    Copy-Item $pitchPNG (Join-Path (Join-Path $pitchConfig.output 'slides') $pitchName) -Force
  }
  $pitchPDF = Join-Path $pitchWork 'Fortop-Pitch.pdf'
  $pitchPresentation.SaveCopyAs($pitchPDF, 32)
  Copy-Item $pitchPDF (Join-Path $pitchConfig.output 'Fortop-Pitch.pdf') -Force
  Write-Output ('PowerPoint rendered ' + $pitchPresentation.Slides.Count + ' slides.')
} finally {
  if ($null -ne $pitchPresentation) { $pitchPresentation.Close() }
  if (($null -ne $pitchApp) -and (-not $pitchExisting)) { $pitchApp.Quit() }
}
'''.replace("__CONFIG__", payload)
    encoded = base64.b64encode(script.encode("utf-16-le")).decode()
    result = subprocess.run([POWERSHELL, "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
                            capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace")[-6000:])
    print(result.stdout.decode(errors="replace").strip())
    for number, slug in enumerate(slugs, 1):
        subprocess.run(["qpdf", "--empty", "--pages", str(ROOT / "Fortop-Pitch.pdf"),
                        str(number), "--", str(ROOT / "slides" / f"{slug}.pdf")], check=True)
    print("Combined PDF and individual slide previews updated.")


if __name__ == "__main__":
    main()
