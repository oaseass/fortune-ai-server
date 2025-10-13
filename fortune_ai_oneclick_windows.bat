@echo off
setlocal ENABLEDELAYEDEXPANSION
title Fortune AI - One Click Setup (Windows)

REM === 0) Preconditions: Python Launcher + Python 3.11 required ===
where py >nul 2>&1 || (
  echo [ERROR] Python Launcher 'py' not found.
  echo Install Python 3.11 (64-bit) from https://www.python.org/downloads/windows/
  pause
  exit /b 1
)
py -3.11 --version >nul 2>&1 || (
  echo [ERROR] Python 3.11 not found.
  echo Please install Python 3.11 (64-bit) and enable "Add python.exe to PATH".
  pause
  exit /b 1
)

REM === 1) Choose project directory (current folder) ===
set "PROJECT_DIR=%cd%\fortune_ai_server_pro_lunar"
if not exist "%PROJECT_DIR%" mkdir "%PROJECT_DIR%"
if not exist "%PROJECT_DIR%\modules" mkdir "%PROJECT_DIR%\modules"

REM === 2) Write files via PowerShell Set-Content (ASCII/UTF8) ===
powershell -NoProfile -Command "$c=@'
fastapi==0.112.2
uvicorn[standard]==0.30.6
python-multipart==0.0.9
pydantic==2.9.1
Pillow==10.4.0
opencv-python-headless==4.10.0.84
mediapipe==0.10.14
openai==1.51.0
python-dotenv==1.0.1
reportlab==4.2.2
lunar_python==1.4.4
'@; Set-Content -Path '%PROJECT_DIR%\requirements.txt' -Value $c -Encoding UTF8"

powershell -NoProfile -Command "$c=@'
OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxx
SERVICE_TOKEN=change-this-service-token
COMPANY_BRAND=운명을보는회사원
'@; Set-Content -Path '%PROJECT_DIR%\.env.example' -Value $c -Encoding UTF8"

powershell -NoProfile -Command "$c=@'
from lunar_python import Solar

def build_saju_meta(y:int, m:int, d:int, H:int, M:int):
    solar = Solar(y, m, d, H, M, 0)
    lunar = solar.getLunar()
    ec = lunar.getEightChar()
    meta = {
        "year": ec.getYear(),
        "month": ec.getMonth(),
        "day": ec.getDay(),
        "time": ec.getTime(),
        "year_wuxing": ec.getYearWuXing(),
        "month_wuxing": ec.getMonthWuXing(),
        "day_wuxing": ec.getDayWuXing(),
        "time_wuxing": ec.getTimeWuXing(),
        "year_tiangan_shishen": ec.getYearShiShenGan(),
        "month_tiangan_shishen": ec.getMonthShiShenGan(),
        "day_tiangan_shishen": ec.getDayShiShenGan(),
        "time_tiangan_shishen": ec.getTimeShiShenGan(),
        "year_dizhi_shishen": list(ec.getYearShiShenZhi() or []),
        "month_dizhi_shishen": list(ec.getMonthShiShenZhi() or []),
        "day_dizhi_shishen": list(ec.getDayShiShenZhi() or []),
        "time_dizhi_shishen": list(ec.getTimeShiShenZhi() or []),
        "jieqi_table": {k: str(v.toYmdHms()) for k,v in (lunar.getJieQiTable() or {}).items()}
    }
    meta["year_ganji"] = meta["year"]
    meta["month_ganji"] = meta["month"]
    meta["day_ganji"]  = meta["day"]
    meta["hour_ganji"] = meta["time"]
    meta["day_master"] = meta["day"][0]
    return meta
'@; Set-Content -Path '%PROJECT_DIR%\modules\saju_lunar.py' -Value $c -Encoding UTF8"

powershell -NoProfile -Command "$c=@'
import numpy as np
import mediapipe as mp

mp_face_mesh = mp.solutions.face_mesh

def analyze_face_landmarks(img_rgb):
    h, w, _ = img_rgb.shape
    with mp_face_mesh.FaceMesh(static_image_mode=True, max_num_faces=1, refine_landmarks=True) as fm:
        res = fm.process(img_rgb)
        if not res.multi_face_landmarks:
            return ("정면 얼굴을 탐지하지 못했습니다. 정면, 밝은 환경의 사진을 권장합니다.", {})
        lm = res.multi_face_landmarks[0]
        pts = [(int(p.x*w), int(p.y*h)) for p in lm.landmark]
    def dist(a,b): return float(np.linalg.norm(np.array(a)-np.array(b)))
    left_eye_outer, right_eye_outer = pts[33], pts[263]
    nose_tip = pts[1]
    mouth_left, mouth_right = pts[61], pts[291]
    chin, forehead = pts[199], pts[10]
    face_w = dist(left_eye_outer, right_eye_outer)
    mouth_w = dist(mouth_left, mouth_right)
    eye_center = ((left_eye_outer[0]+right_eye_outer[0])//2, (left_eye_outer[1]+right_eye_outer[1])//2)
    eye_nose = dist(eye_center, nose_tip)
    chin_forehead = dist(chin, forehead)
    ratios = {
        "얼굴폭": round(face_w,2),
        "입폭": round(mouth_w,2),
        "눈중심-코끝": round(eye_nose,2),
        "이마-턱 길이": round(chin_forehead,2),
        "입/얼굴폭 비율": round(mouth_w/max(face_w,1),3),
        "이마턱/얼굴폭 비율": round(chin_forehead/max(face_w,1),3)
    }
    summary=[]
    if ratios["입/얼굴폭 비율"]<0.32: summary.append("입이 상대적으로 작아 신중·분석형 경향.")
    elif ratios["입/얼굴폭 비율"]>0.38: summary.append("입이 넓어 표현력·사교성이 좋음.")
    else: summary.append("입폭이 균형적이라 대인관계가 안정적.")
    if ratios["이마턱/얼굴폭 비율"]>1.6: summary.append("세로 비율이 길어 집중력·지구력이 좋음.")
    else: summary.append("가로 비율이 상대적으로 커 실용적·현실 감각이 뛰어남.")
    return (" ".join(summary), ratios)
'@; Set-Content -Path '%PROJECT_DIR%\modules\face.py' -Value $c -Encoding UTF8"

powershell -NoProfile -Command "$c=@'
from io import BytesIO
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import mm
from reportlab.lib import colors

def wrap_lines(text, max_chars):
    text = text or ""
    return [text[i:i+max_chars] for i in range(0, len(text), max_chars)]

def build_pdf(brand:str, payload:dict)->bytes:
    buff = BytesIO()
    c = canvas.Canvas(buff, pagesize=A4)
    W,H = A4
    def t(x,y,s,b=False,z=12): c.setFont("Helvetica-Bold" if b else "Helvetica", z); c.drawString(x,y,s)
    c.setFillColor(colors.black)
    t(20*mm, H-20*mm, f"{brand} - AI 종합 운세 리포트", True, 16)
    c.line(20*mm, H-21*mm, W-20*mm, H-21*mm)
    y = H-35*mm
    name = payload.get("name","")
    an = payload.get("analysis",{})
    t(20*mm, y, f"의뢰인: {name}"); y-=8*mm
    for label,key in [("사주 요약","saju_summary"),("관상 요약","face_summary"),("종합 해석","combined_summary")]:
        t(20*mm,y,label,True); y-=7*mm
        for line in wrap_lines(an.get(key,""),90): t(20*mm,y,line); y-=6*mm
        y-=4*mm
    lucky = an.get("lucky",{})
    t(20*mm,y,"행운 요소",True); y-=7*mm
    t(20*mm,y,f"색상: {', '.join(lucky.get('color', []))} / 숫자: {', '.join(map(str,lucky.get('number', [])))} / 방향: {lucky.get('direction','')}"); y-=10*mm
    c.setFillColor(colors.grey); t(20*mm,15*mm,"※ 본 리포트는 참고용이며, 중요한 의사결정은 전문가와 상의하세요.",False,9)
    c.showPage(); c.save()
    return buff.getvalue()
'@; Set-Content -Path '%PROJECT_DIR%\modules\pdf_report.py' -Value $c -Encoding UTF8"

powershell -NoProfile -Command "$c=@'
import io, os, random
from typing import Optional, List
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Header, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from PIL import Image
import numpy as np
from dotenv import load_dotenv

from modules.saju_lunar import build_saju_meta
from modules.face import analyze_face_landmarks
from modules.pdf_report import build_pdf

from openai import OpenAI

load_dotenv()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
SERVICE_TOKEN = os.getenv("SERVICE_TOKEN")
BRAND = os.getenv("COMPANY_BRAND","운명을보는회사원")
client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None

app = FastAPI(title="Fortune AI Server PRO (lunar_python)", version="1.2.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

class Lucky(BaseModel):
    color: List[str]; number: List[int]; direction: str

class AnalyzeResponse(BaseModel):
    saju_summary: str
    face_summary: str
    combined_summary: str
    lucky: Lucky
    saju_meta: dict
    face_meta: dict

def require_token(auth: Optional[str]):
    if SERVICE_TOKEN:
        if not auth or not auth.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="인증 토큰 필요")
        if auth.split(" ",1)[1].strip() != SERVICE_TOKEN:
            raise HTTPException(status_code=403, detail="토큰 불일치")

@app.get("/health")
def health():
    return {"ok": True, "brand": BRAND}

def call_openai_saju(prompt: str) -> str:
    if client is None:
        return "API 키가 없어 예시 해석만 제공합니다."
    try:
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role":"user","content":prompt}],
            temperature=0.7,
        )
        return resp.choices[0].message.content.strip()
    except Exception as e:
        return f"사주 해석 오류: {e}"

def build_saju_prompt(name, gender, calendar_type, birthdate, birthtime, meta):
    return (
        f"[사주 해석]\n"
        f"- 이름: {name}\n- 성별: {gender}\n- 달력: {calendar_type}\n- 생년월일: {birthdate}\n- 태어난 시: {birthtime}\n"
        f"- 간지(년/월/일/시): {meta['year_ganji']} / {meta['month_ganji']} / {meta['day_ganji']} / {meta['hour_ganji']}\n"
        f"- 일간: {meta['day_master']}\n"
        f"- 오행(년/월/일/시): {meta['year_wuxing']} / {meta['month_wuxing']} / {meta['day_wuxing']} / {meta['time_wuxing']}\n\n"
        "위 정보를 반영하여 한국어로: 1) 총평(2~3문장) 2) 재물운 3) 애정운 4) 건강운 5) 오늘의 한 줄 조언 (간결하게)."
    )

def lucky_of_the_day(seed: str) -> Lucky:
    random.seed(seed)
    colors = [["네이비","블랙","그레이"],["버건디","아이보리","브라운"],["그린","화이트","골드"]]
    directions = ["북","남","동","서","북동","남서"]
    nums = [random.randint(1,60) for _ in range(6)]
    return Lucky(color=random.choice(colors), number=sorted(nums), direction=random.choice(directions))

@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze(
    name: str = Form(...),
    gender: str = Form(...),
    calendarType: str = Form("solar"),
    birthdate: str = Form(...),
    birthtime: str = Form("12:00"),
    file: UploadFile = File(...),
    authorization: Optional[str] = Header(None)
):
    require_token(authorization)

    try:
        y,m,d = map(int, birthdate.split("-"))
    except Exception:
        raise HTTPException(status_code=400, detail="birthdate는 YYYY-MM-DD 형식")
    try:
        H,M = map(int, birthtime.split(":")) if ":" in birthtime else (12,0)
    except Exception:
        H,M = 12,0

    content = await file.read()
    try:
        img = Image.open(io.BytesIO(content)).convert("RGB")
    except Exception:
        raise HTTPException(status_code=400, detail="이미지 파싱 실패")
    img_rgb = np.array(img)

    face_summary, face_meta = analyze_face_landmarks(img_rgb)
    saju_meta = build_saju_meta(y,m,d,H,M)
    saju_prompt = build_saju_prompt(name, gender, calendarType, birthdate, birthtime, saju_meta)
    saju_summary = call_openai_saju(saju_prompt)

    combined_summary = (
        f"종합 해석: 일간({saju_meta['day_master']}) 성향과 얼굴 비율 특징을 함께 고려하면 중요한 선택에서 신중함과 추진력을 균형 있게 쓰는 것이 유리합니다. [관상] {face_summary}"
    )
    lucky = lucky_of_the_day(seed=birthdate + (birthtime or ""))

    return AnalyzeResponse(
        saju_summary=saju_summary,
        face_summary=face_summary,
        combined_summary=combined_summary,
        lucky=lucky,
        saju_meta=saju_meta,
        face_meta=face_meta
    )

class ReportIn(BaseModel):
    name: str
    input: dict
    analysis: dict

@app.post("/report")
def report(data: ReportIn, authorization: Optional[str] = Header(None)):
    require_token(authorization)
    pdf_bytes = build_pdf(BRAND, {"name": data.name, "analysis": data.analysis})
    return Response(content=pdf_bytes, media_type="application/pdf",
                    headers={"Content-Disposition": f"attachment; filename=\"{data.name}_fortune_report.pdf\""})
'@; Set-Content -Path '%PROJECT_DIR%\main.py' -Value $c -Encoding UTF8"

REM Minimal README
powershell -NoProfile -Command "$c=@'
# Fortune AI One-Click (Windows)
- 이 폴더에서: run_oneclick.bat 실행
- 처음 실행: venv 생성, pip 설치, .env 준비, 서버 실행
- 브라우저: http://127.0.0.1:8000/docs
'@; Set-Content -Path '%PROJECT_DIR%\README.txt' -Value $c -Encoding UTF8"

REM === 3) Create venv using Python 3.11 ===
pushd "%PROJECT_DIR%"
if not exist ".venv" (
  echo Creating venv with Python 3.11 ...
  py -3.11 -m venv .venv || (echo [ERROR] venv failed & pause & exit /b 1)
)

REM === 4) Activate venv and install requirements ===
call .venv\Scripts\activate || (echo [ERROR] venv activate failed & pause & exit /b 1)
py -3.11 -m pip install --upgrade pip
py -3.11 -m pip install -r requirements.txt || (echo [ERROR] pip install failed & pause & exit /b 1)

REM === 5) Ensure .env exists ===
if not exist ".env" (
  copy ".env.example" ".env" >nul
  echo Open .env and set OPENAI_API_KEY and SERVICE_TOKEN.
  notepad ".env"
)

REM === 6) Launch server ===
echo Starting server at http://127.0.0.1:8000 ...
start "" cmd /k ".venv\Scripts\activate && uvicorn main:app --host 127.0.0.1 --port 8000 --reload"
start "" "http://127.0.0.1:8000/docs"

echo Done. Press any key to close this window...
pause >nul
popd
