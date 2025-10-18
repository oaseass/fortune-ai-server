# ===============================
# wire_modusaju.ps1 (v2)
# - External SAJU API adapter (e.g., 모두의사주) wiring
# - Patch main.py for PRO mode
# - Git commit & push (PowerShell-safe)
# ===============================

param(
  [string]$RepoDir = "C:\fortune_ai_server_pro_lunar",
  [string]$ProSajuUrl = "https://<VENDOR_DOMAIN>/v1/saju",
  [string]$ProSajuKey = "<YOUR_VENDOR_API_KEY>",
  [string]$ProAuthHeader = "Authorization",
  [string]$ProAuthPrefix = "Bearer "
)

function Fail($msg){
  Write-Host "[FAIL] $msg" -ForegroundColor Red
  exit 1
}

function Ok($msg){
  Write-Host "[OK]  $msg" -ForegroundColor Green
}

# 0) sanity
if(!(Test-Path $RepoDir)){ Fail "RepoDir not found: $RepoDir" }
Set-Location $RepoDir

git rev-parse --is-inside-work-tree *> $null 2>&1
if($LASTEXITCODE -ne 0){ Fail "Not a git repository: $RepoDir" }

# 1) write adapter
$adapterPath = Join-Path $RepoDir "saju_pro_adapter.py"
$adapterCode = @'
# -*- coding: utf-8 -*-
"""
saju_pro_adapter.py : external SAJU API adapter
- Configure via env PRO_SAJU_URL/KEY or hardcoded below.
- Map vendor response -> server common schema.
"""
import os, requests

PRO_SAJU_URL = os.getenv("PRO_SAJU_URL", "").strip() or "{URL}"
PRO_SAJU_KEY = os.getenv("PRO_SAJU_KEY", "").strip() or "{KEY}"
PRO_AUTH_HEADER = os.getenv("PRO_SAJU_AUTH_HEADER", "").strip() or "{HDR}"
PRO_AUTH_PREFIX = os.getenv("PRO_SAJU_AUTH_PREFIX", "").strip() or "{PFX}"

class ProSajuError(Exception):
    ...

def _build_headers():
    hdrs = {"Accept": "application/json"}
    if PRO_AUTH_HEADER:
        token = f"{PRO_AUTH_PREFIX}{PRO_SAJU_KEY}".strip()
        hdrs[PRO_AUTH_HEADER] = token
    return hdrs

def fetch_pro_saju(meta: dict) -> dict:
    if not PRO_SAJU_URL or not PRO_SAJU_KEY:
        raise ProSajuError("PRO_SAJU_URL/KEY not set")

    payload = {
        "name": meta.get("name") or "",
        "gender": meta.get("gender") or "unknown",
        "calendar": meta.get("calendarType") or "solar",
        "birthdate": meta.get("birthdate") or "",
        "birthtime": meta.get("birthtime") or "unknown"
    }

    try:
        r = requests.post(PRO_SAJU_URL, json=payload, headers=_build_headers(), timeout=25)
    except Exception as e:
        raise ProSajuError(f"vendor connect error: {e}") from e

    if r.status_code != 200:
        raise ProSajuError(f"vendor http {r.status_code}: {r.text[:300]}")

    try:
        data = r.json()
    except Exception:
        raise ProSajuError(f"vendor json parse error: {r.text[:300]}")

    # naive normalization; replace with exact keys after vendor sample provided
    gsum = data.get("face_summary") or data.get("gwansang") or ""
    ssum = data.get("saju_summary") or data.get("analysis") or ""
    csum = data.get("combined_summary") or data.get("overall") or ""

    lucky = data.get("lucky") or {}
    colors = lucky.get("colors") or data.get("lucky_colors") or []
    numbers = lucky.get("numbers") or data.get("lucky_numbers") or []
    direction = lucky.get("direction") or data.get("lucky_direction") or ""

    return {
        "gwansang_summary": gsum,
        "saju_summary": ssum,
        "combined_summary": csum,
        "lucky": {
            "colors": colors if isinstance(colors, list) else [],
            "numbers": numbers if isinstance(numbers, list) else [],
            "direction": direction or ""
        }
    }
'@
$adapterCode = $adapterCode.Replace("{URL}", $ProSajuUrl).Replace("{KEY}", $ProSajuKey).Replace("{HDR}", $ProAuthHeader).Replace("{PFX}", $ProAuthPrefix)
$adapterCode | Set-Content -Path $adapterPath -Encoding UTF8
Ok "wrote saju_pro_adapter.py"

# 2) patch main.py
$mainPath = Join-Path $RepoDir "main.py"
if(!(Test-Path $mainPath)){ Fail "main.py not found: $mainPath" }

$backup = "$mainPath.bak_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $mainPath $backup
Ok "backup -> $backup"

$main = Get-Content $mainPath -Raw -Encoding UTF8

$patchImport = @"
# === PRO SAJU adapter ===
try:
    from saju_pro_adapter import fetch_pro_saju, ProSajuError
except Exception:
    fetch_pro_saju = None
    class ProSajuError(Exception): ...
"@

$patchLogic = @"
        # === PRO mode (external SAJU API) ===
        pro_enabled = bool(os.getenv('PRO_SAJU_URL') or '{URL}'.startswith('http'))
        pro_key_ok  = bool(os.getenv('PRO_SAJU_KEY') or '{KEY}')

        saju_summary = locals().get('saju_summary','')
        combined_summary = locals().get('combined_summary','')
        lucky = locals().get('lucky', {{ 'colors': [], 'numbers': [], 'direction': '' }})

        if pro_enabled and pro_key_ok and fetch_pro_saju:
            try:
                norm = fetch_pro_saju(meta)
                if isinstance(norm, dict):
                    saju_summary = norm.get('saju_summary') or saju_summary
                    combined_summary = norm.get('combined_summary') or combined_summary
                    if isinstance(norm.get('lucky'), dict):
                        lucky.update(norm['lucky'])
            except ProSajuError as e:
                print(f'[WARN] PRO SAJU failed: {e}')
"@

# add import patch once
if($main -notmatch "from saju_pro_adapter import fetch_pro_saju"){
  $main = $main -replace "(?s)(from fastapi.*?\n)", "`$1`n$patchImport`n"
}

# inject logic after meta dict
if($main -match "meta\s*=\s*{"){
  if($main -notmatch "PRO mode \(external SAJU API\)"){
    $main = $main -replace "(meta\s*=\s*{[^}]+}\s*)", "`$1`n$patchLogic`n"
    $main = $main.Replace("{URL}", $ProSajuUrl).Replace("{KEY}", $ProSajuKey)
  }
} else {
  Fail "could not find 'meta = {' block in main.py"
}

$main | Set-Content -Path $mainPath -Encoding UTF8
Ok "patched main.py"

# 3) git add/commit/push (PowerShell-safe)
git add saju_pro_adapter.py main.py
if ($LASTEXITCODE -ne 0) { Fail "git add failed" }

git commit -m "feat(pro-saju): external SAJU API adapter & PRO mode wiring"
if ($LASTEXITCODE -ne 0) {
  Write-Host "[WARN] nothing to commit or commit failed"
}

git push origin main
if ($LASTEXITCODE -ne 0) { Fail "git push failed (check token/remote)" }

Write-Host "==============================================="
Write-Host "DONE. Now set these on Render and redeploy:"
Write-Host "  PRO_SAJU_URL = $ProSajuUrl"
Write-Host "  PRO_SAJU_KEY = <your key>"
Write-Host "  PRO_SAJU_AUTH_HEADER = $ProAuthHeader"
Write-Host "  PRO_SAJU_AUTH_PREFIX = $ProAuthPrefix"
Write-Host "Manual Deploy on Render to apply."
Write-Host "==============================================="
