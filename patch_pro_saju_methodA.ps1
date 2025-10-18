param(
  [string]$RepoDir = "C:\fortune_ai_server_pro_lunar",
  [string]$ProSajuUrl = "https://<VENDOR_DOMAIN>/v1/saju",
  [string]$ProSajuKey = "<YOUR_VENDOR_API_KEY>",
  [string]$ProAuthHeader = "Authorization",
  [string]$ProAuthPrefix = "Bearer ",
  [switch]$GitPush = $false
)

function Fail($m){ Write-Host "[FAIL] $m" -f Red; exit 1 }
function Ok($m){ Write-Host "[OK]  $m" -f Green }

# 0) 준비
if(!(Test-Path $RepoDir)){ Fail "RepoDir not found: $RepoDir" }
Set-Location $RepoDir
if(!(Test-Path ".\main.py")){ Fail "main.py not found in $RepoDir" }

# 1) saju_pro_adapter.py 쓰기
$adapter = @"
# -*- coding: utf-8 -*-
import os, requests

PRO_SAJU_URL = os.getenv("PRO_SAJU_URL", "").strip() or "$ProSajuUrl"
PRO_SAJU_KEY = os.getenv("PRO_SAJU_KEY", "").strip() or "$ProSajuKey"
PRO_AUTH_HEADER = os.getenv("PRO_SAJU_AUTH_HEADER", "").strip() or "$ProAuthHeader"
PRO_AUTH_PREFIX = os.getenv("PRO_SAJU_AUTH_PREFIX", "").strip() or "$ProAuthPrefix"

class ProSajuError(Exception): ...

def _hdr():
    h = {"Accept":"application/json"}
    if PRO_AUTH_HEADER:
        h[PRO_AUTH_HEADER] = f"{PRO_AUTH_PREFIX}{PRO_SAJU_KEY}".strip()
    return h

def fetch_pro_saju(meta:dict)->dict:
    if not PRO_SAJU_URL or not PRO_SAJU_KEY:
        raise ProSajuError("PRO_SAJU_URL/KEY not set")

    payload = {
        "name":        meta.get("name",""),
        "gender":      meta.get("gender","unknown"),
        "calendar":    meta.get("calendarType","solar"),
        "birthdate":   meta.get("birthdate",""),
        "birthtime":   meta.get("birthtime","unknown"),
    }
    r = requests.post(PRO_SAJU_URL, json=payload, headers=_hdr(), timeout=25)
    if r.status_code != 200:
        raise ProSajuError(f"vendor http {r.status_code}: {r.text[:300]}")
    d = r.json()

    # 벤더 응답 키를 표준형으로 매핑 (필요시 여기만 조정)
    g = d.get("face_summary") or d.get("gwansang") or ""
    s = d.get("saju_summary") or d.get("analysis") or ""
    c = d.get("combined_summary") or d.get("overall") or ""
    L = d.get("lucky") or {}

    return {
        "gwansang_summary": g,
        "saju_summary": s,
        "combined_summary": c,
        "lucky": {
            "colors": L.get("colors", []),
            "numbers": L.get("numbers", []),
            "direction": L.get("direction", ""),
        }
    }
"@
$adapter | Set-Content -Path ".\saju_pro_adapter.py" -Encoding UTF8
Ok "saju_pro_adapter.py written"

# 2) main.py 백업 & 로드
$mainPath = ".\main.py"
$backup = "$mainPath.bak_$(Get-Date -f yyyyMMdd_HHmmss)"
Copy-Item $mainPath $backup -Force
Ok "backup -> $backup"

$text = Get-Content $mainPath -Raw -Encoding UTF8

# 3) import 주입 (fastapi import 바로 아래에)
if($text -notmatch "saju_pro_adapter"){
  $text = $text -replace "(?s)(from\s+fastapi[^\r\n]*\r?\n)",
  "`$1# === PRO SAJU adapter (auto) ===`r`ntry:`r`n    from saju_pro_adapter import fetch_pro_saju, ProSajuError`r`nexcept Exception:`r`n    fetch_pro_saju=None`r`n    class ProSajuError(Exception): ...`r`n"
  Ok "import block injected"
} else {
  Ok "import block already present"
}

# 4) PRO 블록 (리턴 직전 주입)
$proBlock = @"
# >>> PRO SAJU START (method A - auto inject)
try:
    # meta 안전 확보
    if 'meta' not in locals():
        _form = await request.form()
        meta = {
            "name": _form.get("name") or "",
            "gender": _form.get("gender") or "unknown",
            "calendarType": _form.get("calendarType") or "solar",
            "birthdate": _form.get("birthdate") or "",
            "birthtime": _form.get("birthtime") or "unknown",
        }
    if fetch_pro_saju:
        _norm = fetch_pro_saju(meta)
        if isinstance(_norm, dict):
            gwansang_summary = locals().get('gwansang_summary', '')
            saju_summary     = locals().get('saju_summary', '')
            combined_summary = locals().get('combined_summary', '')
            lucky            = locals().get('lucky', {"colors":[],"numbers":[],"direction":""})

            if _norm.get('gwansang_summary'): gwansang_summary = _norm['gwansang_summary']
            if _norm.get('saju_summary'):     saju_summary     = _norm['saju_summary']
            if _norm.get('combined_summary'): combined_summary = _norm['combined_summary']
            if isinstance(_norm.get('lucky'), dict): lucky.update(_norm['lucky'])

            result = {
                "ok": True,
                "meta": meta,
                "gwansang_summary": gwansang_summary,
                "saju_summary": saju_summary,
                "combined_summary": combined_summary,
                "bbox": locals().get("bbox", None),
                "lucky": lucky,
            }
            return JSONResponse(result) if 'JSONResponse' in globals() else result
except Exception as _e:
    print(f"[WARN] PRO block error: {_e}")
# <<< PRO SAJU END
"@

# 우선순위: return JSONResponse( -> return { -> 파일 끝에 안전추가
if($text -match "return\s+JSONResponse\("){
  $text = $text -replace "return\s+JSONResponse\(", "$proBlock`r`nreturn JSONResponse("
  Ok "injected before 'return JSONResponse('"
} elseif($text -match "return\s*{"){
  $text = $text -replace "return\s*{", "$proBlock`r`nreturn {"
  Ok "injected before 'return {'"
} else {
  $text += "`r`n# [AUTO-APPEND NOTE] Place the following PRO block just before your final return in /analyze:`r`n$proBlock`r`n"
  Ok "could not locate return; appended block with note"
}

# 5) 저장
$text | Set-Content -Path $mainPath -Encoding UTF8
Ok "main.py saved"

# 6) Git 커밋/푸시 (옵션)
git rev-parse --is-inside-work-tree *> $null 2>&1
if($LASTEXITCODE -eq 0){
  git add main.py saju_pro_adapter.py | Out-Null
  git commit -m "feat(pro-saju A): inject PRO block before return & adapter" | Out-Null
  Ok "git commit done"
  if($GitPush){ git push origin main; if($LASTEXITCODE -ne 0){ Fail "git push failed" } else { Ok "git push done" } }
} else {
  Write-Host "[WARN] not a git repo; skipping commit" -f Yellow
}

Write-Host "==============================================="
Write-Host "Render 환경변수 확인 후 재배포하세요:"
Write-Host "  PRO_SAJU_URL         = $ProSajuUrl"
Write-Host "  PRO_SAJU_KEY         = <발급키>"
Write-Host "  PRO_SAJU_AUTH_HEADER = $ProAuthHeader"
Write-Host "  PRO_SAJU_AUTH_PREFIX = $ProAuthPrefix"
Write-Host "그리고:"
Write-Host "  SERVICE_TOKEN  = (WP와 동일)"
Write-Host "  ALLOW_ORIGINS  = https://워드프레스도메인  (테스트는 *)"
Write-Host "==============================================="
