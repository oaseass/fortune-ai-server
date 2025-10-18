# ==================== enable_openai_backend.ps1 ====================
# 목적: 기존 FastAPI 서버에 OpenAI 연동(전문 사주/관상 요약 생성) 경로를 추가하고
#       Render로 재배포까지 자동화.

param(
  [string]$RepoUrl = "https://github.com/oaseass/fortune-ai-server.git",
  [string]$Branch  = "main"
)

$ErrorActionPreference = "Stop"
function Info($m){ Write-Host "[INFO]" $m -ForegroundColor Cyan }
function Done($m){ Write-Host "[OK]"   $m -ForegroundColor Green }
function Fail($m){ Write-Host "[FAIL]" $m -ForegroundColor Red; exit 1 }

# 0) 위치 이동
Push-Location "C:\fortune_ai_server_pro_lunar"

# 1) main.py 백업
if (Test-Path ".\main.py") {
  Copy-Item ".\main.py" ".\main.py.bak_openai" -Force
  Info "main.py 백업 완료 -> main.py.bak_openai"
} else { Fail "main.py를 찾지 못했습니다." }

# 2) OpenAI 연동 코드 삽입/갱신
#    - OPENAI_API_KEY 가 있으면 LLM으로 전문 결과 생성
#    - 기존 analyze 로직은 face bbox/lunar-python 메타까지 그대로 활용
$py = Get-Content ".\main.py" -Raw

# 이미 패치되어 있으면 스킵
if ($py -match "# === OPENAI_VENDOR_BEGIN ===") {
  Info "이미 OpenAI 패치가 적용되어 있어 코드 부분은 건너뜁니다."
} else {
  $inject = @'
# === OPENAI_VENDOR_BEGIN ===
import os, json, requests

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "").strip()
OPENAI_BASE    = os.environ.get("OPENAI_BASE", "https://api.openai.com/v1").strip()
OPENAI_MODEL   = os.environ.get("OPENAI_MODEL", "gpt-4o-mini").strip()

def _build_prompt(meta: dict, gwansang_summary: str, simple_lucky: dict) -> str:
    """
    LLM에게 줄 프롬프트. 사주(연월일시·오행·용희신), 관상요지(존재하면),
    연/대운/세운 흐름, 직업/재물/대인/건강, 구체적 행운 포인트까지
    한국어 전문가 톤으로 길고 정리된 보고서 생성 요구.
    """
    return f"""
당신은 한국의 전문 명리/관상 컨설턴트입니다. 아래 메타와 요약을 바탕으로,
1) 사주 핵심 구조(일간, 오행 편중, 용희신) 해석
2) 성향·강점·리스크, 유의점
3) 재물/커리어/대인관계/건강 관점 제안
4) 10년 대운(2구간) 개요, 최근 2년 세운 포인트
5) 관상 포인트가 있으면 보완·보정 코멘트
6) 구체적 행운 포인트(색상·숫자·방향을 메타에 맞게 개선)

메타:
{json.dumps(meta, ensure_ascii=False, indent=2)}

관상요약(없으면 생략해도 됨):
{gwansang_summary or "없음"}

기본 행운(서버 내 계산):
{json.dumps(simple_lucky, ensure_ascii=False, indent=2)}

형식:
- 사주 요약: ...
- 관상 요약: ...
- 종합 요약: ...
- 행운 포인트:
  - 색상: 3~5개 구체 색이름(한글)
  - 숫자: 3개
  - 방향: 구체 방위(예: 북북동)
- 대운: [{"start": 2026, "end": 2035, "note":"..."}, ...]
- 세운: [{"year": 2025, "note":"..."},{"year": 2026, "note":"..."}]
문장체 한국어, 실무적이고 과장 없는 전문가 톤으로 자세히 작성.
"""
def call_openai_vendor(meta: dict, gwansang_summary: str, base_lucky: dict) -> dict:
    if not OPENAI_API_KEY:
        return {}
    headers = {
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json",
    }
    prompt = _build_prompt(meta, gwansang_summary, base_lucky)
    body = {
        "model": OPENAI_MODEL,
        "messages": [
            {"role":"system","content":"당신은 신뢰할 수 있는 한국어 명리/관상 컨설턴트입니다."},
            {"role":"user","content": prompt}
        ],
        "temperature": 0.6,
    }
    try:
        url = f"{OPENAI_BASE}/chat/completions"
        r = requests.post(url, headers=headers, json=body, timeout=60)
        r.raise_for_status()
        txt = r.json()["choices"][0]["message"]["content"]
        # 매우 간단한 파서: 섹션 라벨로 분해(실무에선 JSON 모드 사용 권장)
        out = {"raw": txt}
        # 라벨 키워드로 나누기
        parts = {
            "saju_summary": "", "gwansang_summary": "", "combined_summary": "",
            "lucky": {"colors":[],"numbers":[],"direction":""},
            "daewoon": [], "sewoon": []
        }
        # 줄 단위 파싱(초간단)
        for line in txt.splitlines():
            L = line.strip()
            if L.startswith("- 사주 요약"):
                parts["section"] = "saju"
            elif L.startswith("- 관상 요약"):
                parts["section"] = "gwan"
            elif L.startswith("- 종합 요약"):
                parts["section"] = "comb"
            elif L.startswith("- 행운 포인트"):
                parts["section"] = "lucky"
            elif L.startswith("- 대운"):
                parts["section"] = "dae"
            elif L.startswith("- 세운"):
                parts["section"] = "se"
            else:
                sec = parts.get("section","")
                if sec=="saju": parts["saju_summary"] += L + "\n"
                elif sec=="gwan": parts["gwansang_summary"] += L + "\n"
                elif sec=="comb": parts["combined_summary"] += L + "\n"
                elif sec=="lucky":
                    if "색상" in L: pass
                    elif "숫자" in L: pass
                    elif "방향" in L: pass
                elif sec=="dae": pass
                elif sec=="se": pass
        return parts
    except Exception as e:
        return {}
# === OPENAI_VENDOR_END ===
'@

  # 간단 삽입: from fastapi import ... 라인 뒤에 붙이기
  if ($py -match "from fastapi import") {
    $py = $py -replace "(from fastapi[^\n]+\n)", "`$1`r`n$inject`r`n"
  } else {
    $py = $inject + "`r`n" + $py
  }

  # analyze 엔드포인트에서 응답 조립 직전에 OpenAI 호출 추가
  # (서버마다 코드가 다르므로, 'result = {'ok': True ...}' 만들기 전/후의 지점에 삽입)
  $py = $py -replace "(#\s*RESULT_BEGIN\s*\n)", "`$1`r`n    # OpenAI 연동(있으면 프로 해석 덮어쓰기)`r`n    try:`r`n        vendor = call_openai_vendor(meta, gwansang_summary, lucky)`r`n        if vendor.get('saju_summary'): saju_summary = vendor['saju_summary'].strip()`r`n        if vendor.get('gwansang_summary'): gwansang_summary = vendor['gwansang_summary'].strip()`r`n        if vendor.get('combined_summary'): combined_summary = vendor['combined_summary'].strip()`r`n        if vendor.get('lucky') and isinstance(vendor['lucky'], dict):`r`n            lucky.update({k:v for k,v in vendor['lucky'].items() if v})`r`n    except Exception as _e:`r`n        pass`r`n"
  Set-Content ".\main.py" $py -Encoding UTF8
  Done "main.py에 OpenAI 연동 코드 삽입 완료"
}

# 3) Git 커밋 & 푸시
git add -A
git commit -m "feat(openai): LLM vendor fallback for pro saju/gwansang"
git branch | Out-Null
git push origin $Branch
Done "GitHub 푸시 완료"

# 4) 안내
Write-Host @"
========================================================
Render 대시보드 → Environment에 아래를 추가하고 Deploy:
- OPENAI_API_KEY = (네 키)
- OPENAI_MODEL = gpt-4o-mini   (선택)
- OPENAI_BASE = https://api.openai.com/v1 (선택)
배포 후 워드프레스에서는 기존과 동일하게 사용하면 됩니다.
========================================================
"@
Pop-Location
# ==================== end of script ====================
