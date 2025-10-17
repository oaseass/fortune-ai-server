# ============================
# upgrade_pro_saju.ps1 (v2)
# ============================

$ErrorActionPreference = "Stop"

# --- 사용자 설정 ---
$RepoPath = "C:\fortune_ai_server_pro_lunar"
$Branch   = "main"
$GitUser  = "oaseass"
$GitEmail = "you@example.com"

Set-Location $RepoPath

# Git 기본 설정
git config --global user.name  $GitUser  | Out-Null
git config --global user.email $GitEmail | Out-Null
try { git fetch --all | Out-Null } catch {}
try { git checkout $Branch  | Out-Null } catch { git checkout -b $Branch | Out-Null }

# 1) 전문 사주 어댑터 파일 생성/갱신
$AdapterPath = Join-Path $RepoPath "saju_pro_adapter.py"
$AdapterCode = @'
import os, json, asyncio
from typing import Dict, Any
import httpx
from lunar_python import Lunar

PRO_SAJU_URL = os.getenv("PRO_SAJU_URL", "").rstrip("/")
PRO_SAJU_KEY = os.getenv("PRO_SAJU_KEY", "")

_CACHE: dict[str, tuple[dict, float]] = {}

def _cache_get(k: str):
    v = _CACHE.get(k)
    if not v: return None
    data, exp = v
    if exp < asyncio.get_event_loop().time():
        _CACHE.pop(k, None)
        return None
    return data

def _cache_set(k: str, data: dict, ttl: int = 86400):
    _CACHE[k] = (data, asyncio.get_event_loop().time() + ttl)

def _to_solar(date_str: str, calendar_type: str) -> str:
    if calendar_type == "lunar":
        y, m, d = map(int, date_str.split("-"))
        lunar = Lunar.fromYmd(y, m, d)
        sol = lunar.getSolar()
        return f"{sol.getYear():04d}-{sol.getMonth():02d}-{sol.getDay():02d}"
    return date_str

async def fetch_saju_from_provider(meta: Dict[str, Any]) -> Dict[str, Any]:
    if not PRO_SAJU_URL or not PRO_SAJU_KEY:
        raise RuntimeError("PRO_SAJU_URL/PRO_SAJU_KEY not set")

    solar = _to_solar(meta["birthdate"], meta["calendarType"])
    hhmm  = meta.get("birthtime") or "12:00"
    if hhmm in ("모름","unknown"): hhmm = "12:00"

    payload = {
        "name": meta["name"],
        "gender": meta["gender"],
        "date": solar,
        "time": hhmm,
        "calendar": "solar",
    }

    ck = json.dumps(payload, sort_keys=True)
    cached = _cache_get(ck)
    if cached: return cached

    headers = {"Authorization": f"Bearer {PRO_SAJU_KEY}", "Content-Type": "application/json"}
    timeout = httpx.Timeout(3.0, connect=3.0)
    last_err = None
    for _ in (1,2):
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                r = await client.post(f"{PRO_SAJU_URL}/analyze", headers=headers, json=payload)
            r.raise_for_status()
            vendor = r.json()
            uni = adapt_vendor_to_unified(vendor, meta)
            _cache_set(ck, uni)
            return uni
        except Exception as e:
            last_err = e
            await asyncio.sleep(0.25)
    raise last_err

def adapt_vendor_to_unified(v: Dict[str, Any], meta: Dict[str, Any]) -> Dict[str, Any]:
    pillars = v.get("pillars", {})
    ten_gods = v.get("ten_gods", {})
    yhs = v.get("yongheeshin", [])
    daewoon = v.get("daewoon", [])
    sewoon = v.get("sewoon", [])
    summary = v.get("summary") or f"{meta['name']}님의 핵심 성향 및 운세 흐름 요약"

    return {
        "ok": True,
        "meta": meta,
        "saju": {
            "pillars": {
                "year": pillars.get("y"),
                "month": pillars.get("m"),
                "day": pillars.get("d"),
                "time": pillars.get("t"),
            },
            "ten_gods": ten_gods,
            "yongheeshin": yhs,
            "luck": {"daewoon": daewoon, "sewoon": sewoon},
        },
        "saju_summary": summary,
    }
'@
Set-Content -Path $AdapterPath -Value $AdapterCode -Encoding UTF8
Write-Host "[OK] saju_pro_adapter.py 갱신"

# 2) main.py 백업 및 패치
$MainPath = Join-Path $RepoPath "main.py"
if (!(Test-Path $MainPath)) { throw "main.py 없음: $MainPath" }

$Backup = "$MainPath.bak_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $MainPath $Backup
Write-Host "[OK] 백업 -> $Backup"

$T = Get-Content $MainPath -Raw

# import 주입
if ($T -notmatch 'from\s+saju_pro_adapter\s+import\s+fetch_saju_from_provider') {
  $T = $T -replace '(\r?\nfrom fastapi[^\r\n]+)', "`$1`r`nfrom saju_pro_adapter import fetch_saju_from_provider"
}

# meta 블록 뒤에 saju 호출 주입 (중복 방지)
if ($T -notmatch 'PRO SAJU INTEGRATION') {
  $inject = @'
        # === PRO SAJU INTEGRATION ===
        saju_part = None
        try:
            saju_part = await fetch_saju_from_provider(meta)
        except Exception:
            saju_part = None
'@
  $T = $T -replace "(\r?\n\s*meta\s*=\s*\{[^\}]+\}\s*\r?\n)", "`$1$inject`r`n"
}

# 응답 조립부의 요약들에 saju_part 우선 적용
$T = $T -replace '("saju_summary"\s*:\s*)[^,]+,', '$1(saju_part["saju_summary"] if saju_part else "데모 계산값 (전문 사주 API 권장)"),'
$T = $T -replace '("combined_summary"\s*:\s*)[^,]+,', '$1(saju_part["saju_summary"] if saju_part else "데모 종합 요약"),'

Set-Content -Path $MainPath -Value $T -Encoding UTF8
Write-Host "[OK] main.py 패치 완료"

# 3) 커밋/푸시
git add -A
git commit -m "feat(pro-saju): add provider adapter + integrate (auto)" | Out-Null
git push origin $Branch

Write-Host ""
Write-Host "==============================================="
Write-Host " 완료! GitHub 푸시까지 끝. (Render 연결이면 자동 재배포)"
Write-Host " Render 환경변수 추가 후 Manual Deploy:"
Write-Host "   PRO_SAJU_URL = https://벤더도메인/v1/saju"
Write-Host "   PRO_SAJU_KEY = <벤더키>"
Write-Host "==============================================="
