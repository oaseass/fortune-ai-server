# patch_render_safe.ps1
param(
  [string]$RepoDir = "C:\fortune_ai_server_pro_lunar",
  [string]$CommitMsg = "fix: robust OpenAI vendor with safe fallback + deps"
)

Set-Location $RepoDir

# 1) requirements.txt 보강
$req = @()
if (Test-Path "$RepoDir\requirements.txt") {
  $req = Get-Content "$RepoDir\requirements.txt"
}
# 필요한 항목들 (중복 방지)
$need = @(
  "fastapi>=0.110",
  "uvicorn[standard]>=0.29",
  "python-multipart>=0.0.7",
  "pydantic>=2",
  "Pillow>=10",
  "openai>=1.51.0"
)
foreach ($line in $need) {
  if ($req -notcontains $line) { $req += $line }
}
$req | Set-Content "$RepoDir\requirements.txt" -Encoding UTF8

# 2) main.py 안전 래퍼 주입
$mainPath = Join-Path $RepoDir "main.py"
$src = Get-Content $mainPath -Raw

# 이미 패치가 들어간 경우 중복 방지용 마커
if ($src -notmatch "# === RICH OPENAI PROVIDER ===") {
$inject = @'
# === RICH OPENAI PROVIDER ===
import os, logging
logger = logging.getLogger("fortune")
logger.setLevel(logging.INFO)

RICH_MODE = os.getenv("RICH_MODE", "0").strip()
SAJU_PROVIDER = (os.getenv("SAJU_PROVIDER") or "").strip().lower()
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_BASE  = os.getenv("OPENAI_BASE", "https://api.openai.com/v1")
OPENAI_KEY   = os.getenv("OPENAI_API_KEY")

try:
    from openai import OpenAI
    _HAS_OPENAI = True
except Exception as _e:
    logger.warning(f"openai import failed: {_e}")
    _HAS_OPENAI = False

def _pro_saju_openai(meta: dict, gwansang: str) -> str:
    """
    OpenAI 호출 – 실패 시 예외가 프로세스를 죽이지 않도록 항상 try/except로 보호.
    결과는 최대 4000자 정도로 절단해 반환.
    """
    if not (_HAS_OPENAI and OPENAI_KEY):
        return "사주 전문 분석은 아직 연결되지 않았습니다. (OPENAI_API_KEY 미설정)"

    try:
        client = OpenAI(api_key=OPENAI_KEY, base_url=OPENAI_BASE)
        prompt = (
            "당신은 한국어 사주/명리 전문가입니다. 아래 인적사항과 관상 요약을 참고하여, "
            "1) 사주 요약(성격, 장단점, 적성), 2) 재물·직업, 3) 인간관계·연애, 4) 건강 유의, "
            "5) 올해/다음해 운세 핵심, 6) 실천 팁을 소제목과 불릿으로 600~900자 내로 고급스럽게 작성하세요.\n\n"
            f"[인적사항]\n{meta}\n\n[관상 요약]\n{gwansang or '관상 데이터 없음'}\n"
        )
        rsp = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[{"role":"user","content":prompt}],
            temperature=0.8,
        )
        text = (rsp.choices[0].message.content or "").strip()
        return text[:4000] if text else "사주 전문 분석 결과를 비워둘 수 없습니다."
    except Exception as e:
        logger.warning(f"openai vendor error: {e}")
        return "사주 전문 분석 호출이 일시적으로 실패했습니다. (벤더 응답 지연/오류)"

def render_rich_results(meta: dict, gwansang: str):
    """
    고급 결과 생성: OpenAI 공급자 사용 조건이 충족될 때만 호출,
    아니면 깔끔한 기본값으로 채움.
    """
    if SAJU_PROVIDER == "openai" and RICH_MODE == "1":
        saju = _pro_saju_openai(meta, gwansang)
    else:
        saju = "사주 전문 분석은 비활성 상태입니다. (RICH_MODE=1, SAJU_PROVIDER=openai 필요)"
    combined = "관상과 사주를 종합해 균형 잡힌 조언을 제공합니다. 장점은 강화하고, 약점은 관리하는 전략을 권합니다."
    lucky = {"colors":["네이비","차콜","화이트"], "numbers":[3,6,9], "direction":"북동"}
    return saju, combined, lucky
# === END RICH OPENAI PROVIDER ===
'@

  # main.py 끝부분(응답 생성 부) 직전에 삽입 – 가장 안전한 위치로 try
  # 단, 프로젝트마다 구조가 다를 수 있어, 최하단에 그냥 추가해도 무방
  $src = $src + "`r`n" + $inject
}

# 3) 엔드포인트에서 새 함수 사용하도록 가드(최소 침습)
# 이름/성별/달력/생일/시간 메타와 gwansang_summary가 준비된 상태라고 가정하고,
# 응답 dict를 구성하는 부분을 패치: 'gwansang_summary','saju_summary','combined_summary','lucky'가 항상 채워지도록.

$src = $src -replace '(return\s+JSONResponse\(\s*\{[^}]+?"ok":\s*True,[\s\S]+?\}\s*\))', '
# --- 안전 응답 빌드 (빈값 방지) ---
try:
    meta = {
        "name": meta.get("name") if "meta" in locals() else (payload.get("name") if "payload" in locals() else None),
        "gender": meta.get("gender") if "meta" in locals() else (payload.get("gender") if "payload" in locals() else None),
        "calendarType": meta.get("calendarType") if "meta" in locals() else (payload.get("calendarType") if "payload" in locals() else None),
        "birthdate": meta.get("birthdate") if "meta" in locals() else (payload.get("birthdate") if "payload" in locals() else None),
        "birthtime": meta.get("birthtime") if "meta" in locals() else (payload.get("birthtime") if "payload" in locals() else None),
    }
except Exception:
    meta = {"name":None,"gender":None,"calendarType":None,"birthdate":None,"birthtime":None}

gw = gwansang_summary if "gwansang_summary" in locals() else None
try:
    saju_text, combined_text, lucky = render_rich_results(meta, gw)
except Exception as e:
    logger.warning(f"rich render error: {e}")
    saju_text, combined_text, lucky = "사주 전문 분석 생성 중 오류가 발생했습니다.", "요약 생성 실패 – 기본 안내로 대체합니다.", {"colors":["블랙"],"numbers":[7],"direction":"북"}

resp = {
    "ok": True,
    "meta": meta,
    "gwansang_summary": gw or "관상 요약이 비어 있습니다.",
    "saju_summary": saju_text or "사주 요약이 비어 있습니다.",
    "combined_summary": combined_text or "종합 요약이 비어 있습니다.",
    "lucky": lucky or {"colors":[],"numbers":[],"direction":"—"}
}
return JSONResponse(resp)
'

Set-Content $mainPath $src -Encoding UTF8

# 4) Git 커밋 & 푸시
git add -A
git commit -m $CommitMsg
git push origin main

Write-Host "`n패치 완료. Render에서 'Save, rebuild and deploy' 후 Logs로 확인하세요.`n" -ForegroundColor Green
