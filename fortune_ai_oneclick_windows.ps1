Param(
  [string]$ProjectName = "fortune_ai_server_pro_lunar"
)

$ErrorActionPreference = "Stop"
Write-Host "=== Fortune AI - One Click PowerShell (Windows) ===" -ForegroundColor Cyan

function Find-Python311 {
  $candidates = @(
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "$env:ProgramFiles\Python311\python.exe",
    "$env:ProgramFiles(x86)\Python311\python.exe"
  )
  foreach ($p in $candidates) { if (Test-Path $p) { return $p } }

  try {
    $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Python\PythonCore\3.11\InstallPath' -ErrorAction Stop
    $exe = Join-Path $reg.(Get-Member -InputObject $reg -MemberType NoteProperty | Select-Object -First 1).Name 'python.exe'
    if (Test-Path $exe) { return $exe }
  } catch {}

  try {
    $regWow = Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore\3.11\InstallPath' -ErrorAction Stop
    $exe = Join-Path $regWow.(Get-Member -InputObject $regWow -MemberType NoteProperty | Select-Object -First 1).Name 'python.exe'
    if (Test-Path $exe) { return $exe }
  } catch {}

  return $null
}

$py311 = Find-Python311
if (-not $py311) {
  Write-Error "Python 3.11 not found. Install 64-bit Python 3.11 first."
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Proj = Join-Path $Root $ProjectName
$Modules = Join-Path $Proj "modules"
New-Item -ItemType Directory -Path $Proj -Force | Out-Null
New-Item -ItemType Directory -Path $Modules -Force | Out-Null

# ---- Write files (UTF-8) ----
@"
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
"@ | Set-Content -Path (Join-Path $Proj "requirements.txt") -Encoding UTF8

@"
OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxx
SERVICE_TOKEN=change-this-service-token
COMPANY_BRAND=운명을보는회사원
"@ | Set-Content -Path (Join-Path $Proj ".env.example") -Encoding UTF8

@"
from lunar_python import Solar

def build_saju_meta(y:int, m:int, d:int, H:int, M:int):
    solar = Solar(y, m, d, H, M, 0)
    lunar = solar.getLunar()
    ec = lunar.getEightChar()
    meta = {
        'year': ec.getYear(),
        'month': ec.getMonth(),
        'day': ec.getDay(),
        'time': ec.getTime(),
        'year_wuxing': ec.getYearWuXing(),
        'month_wuxing': ec.getMonthWuXing(),
        'day_wuxing': ec.getDayWuXing(),
        'time_wuxing': ec.getTimeWuXing(),
        'year_tiangan_shishen': ec.getYearShiShenGan(),
        'month_tiangan_shishen': ec.getMonthShiShenGan(),
        'day_tiangan_shishen': ec.getDayShiShenGan(),
        'time_tiangan_shishen': ec.getTimeShiShenGan(),
        'year_dizhi_shishen': list(ec.getYearShiShenZhi() or []),
        'month_dizhi_shishen': list(ec.getMonthShiShenZhi() or []),
        'day_dizhi_shishen': list(ec.getDayShiShenZhi() or []),
        'time_dizhi_shishen': list(ec.getTimeShiShenZhi() or []),
        'jieqi_table': {k: str(v.toYmdHms()) for k,v in (lunar.getJieQiTable() or {}).items()}
    }
    meta['year_ganji'] = meta['year']
    meta['month_ganji'] = meta['month']
    meta['day_ganji']  = meta['day']
    meta['hour_ganji'] = meta['time']
    meta['day_master'] = meta['day'][0]
    return meta
"@ | Set-Content -Path (Join-Path $Modules "saju_lunar.py") -Encoding UTF8

@"
import numpy as np
import mediapipe as mp

mp_face_mesh = mp.solutions.face_mesh

def analyze_face_landmarks(img_rgb):
    h, w, _ = img_rgb.shape
    with mp_face_mesh.FaceMesh(static_image_mode=True, max_num_faces=1, refine_landmarks=True) as fm:
        res = fm.process(img_rgb)
        if not res.multi_face_landmarks:
            return ('No frontal face detected. Use a frontal, well-lit photo.', {})
        lm = res.multi_face_landmarks[0]
        pts = [(int(p.x*w), int(p.y*h)) for p in lm.landmark]
    def dist(a,b):
        return float(np.linalg.norm(np.array(a)-np.array(b)))
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
        'face_w': round(face_w,2),
        'mouth_w': round(mouth_w,2),
        'eye_to_nose': round(eye_nose,2),
        'chin_to_forehead': round(chin_forehead,2),
        'mouth_over_face': round(mouth_w/max(face_w,1),3),
        'vert_over_face': round(chin_forehead/max(face_w,1),3)
    }
    summary=[]
    summary.append('mouth balanced' if 0.32 <= ratios['mouth_over_face'] <= 0.38 else ('mouth narrow' if ratios['mouth_over_face'] < 0.32 else 'mouth wide'))
    summary.append('vertical long' if ratios['vert_over_face'] > 1.6 else 'horizontal relatively wide')
    return ('; '.join(summary), ratios)
"@ | Set-Content -Path (Join-Path $Modules "face.py") -Encoding UTF8

@"
from io import BytesIO
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import mm
from reportlab.lib import colors

def wrap_lines(text, max_chars):
    text = text or ''
    return [text[i:i+max_chars] for i in range(0, len(text), max_chars)]

def build_pdf(brand:str, payload:dict)->bytes:
    buff = BytesIO()
    c = canvas.Canvas(buff, pagesize=A4)
    W,H = A4
    def t(x,y,s,b=False,z=12):
        c.setFont('Helvetica-Bold' if b else 'Helvetica', z); c.drawString(x,y,s)
    c.setFillColor(colors.black)
    t(20*mm, H-20*mm, f'{brand} - AI Report', True, 16)
    c.line(20*mm, H-21*mm, W-20*mm, H-21*mm)
    y = H-35*mm
    name = payload.get('name','')
    an = payload.get('analysis',{})
    t(20*mm, y, f'Client: {name}'); y-=8*mm
    for label,key in [('Saju','saju_summary'),('Face','face_summary'),('Combined','combined_summary')]:
        t(20*mm,y,label,True); y-=7*mm
        for line in wrap_lines(an.get(key,''),90):
            t(20*mm,y,line); y-=6*mm
        y-=4*mm
    lucky = an.get('lucky',{})
    t(20*mm,y,'Lucky',True); y-=7*mm
    t(20*mm,y,f"color: {', '.join(lucky.get('color', []))} / number: {', '.join(map(str,lucky.get('number', [])))} / dir: {lucky.get('direction','')}"); y-=10*mm
    c.setFillColor(colors.grey); t(20*mm,15*mm,'* For reference only.',False,9)
    c.showPage(); c.save()
    return buff.getvalue()
"@ | Set-Content -Path (Join-Path $Modules "pdf_report.py") -Encoding UTF8

@"
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
OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
SERVICE_TOKEN = os.getenv('SERVICE_TOKEN')
BRAND = os.getenv('COMPANY_BRAND','FortuneBrand')
client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None

app = FastAPI(title='Fortune AI Server PRO', version='1.2.0')
app.add_middleware(CORSMiddleware, allow_origins=['*'], allow_credentials=True, allow_methods=['*'], allow_headers=['*'])

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
        if not auth or not auth.startswith('Bearer '):
            raise HTTPException(status_code=401, detail='token required')
        if auth.split(' ',1)[1].strip() != SERVICE_TOKEN:
            raise HTTPException(status_code=403, detail='invalid token')

@app.get('/health')
def health():
    return {'ok': True, 'brand': BRAND}

def call_openai_saju(prompt: str) -> str:
    if client is None:
        return 'No API key: demo summary.'
    try:
        resp = client.chat.completions.create(
            model='gpt-4o-mini',
            messages=[{'role':'user','content':prompt}],
            temperature=0.7,
        )
        return resp.choices[0].message.content.strip()
    except Exception as e:
        return f'err: {e}'

def build_saju_prompt(name, gender, calendar_type, birthdate, birthtime, meta):
    return (
        f"[SAJU]\n- name: {name}\n- gender: {gender}\n- cal: {calendar_type}\n- dob: {birthdate}\n- time: {birthtime}\n"
        f"- ganji: {meta['year_ganji']} / {meta['month_ganji']} / {meta['day_ganji']} / {meta['hour_ganji']}\n"
        f"- day_master: {meta['day_master']}\n"
        f"- wuxing: {meta['year_wuxing']} / {meta['month_wuxing']} / {meta['day_wuxing']} / {meta['time_wuxing']}\n\n"
        'Make Korean summary: 1) total 2) money 3) love 4) health 5) one-line advice.'
    )

def lucky_of_the_day(seed: str) -> Lucky:
    random.seed(seed)
    colors = [['네이비','블랙','그레이'],['버건디','아이보리','브라운'],['그린','화이트','골드']]
    directions = ['북','남','동','서','북동','남서']
    nums = [random.randint(1,60) for _ in range(6)]
    return Lucky(color=random.choice(colors), number=sorted(nums), direction=random.choice(directions))

@app.post('/analyze', response_model=AnalyzeResponse)
async def analyze(
    name: str = Form(...),
    gender: str = Form(...),
    calendarType: str = Form('solar'),
    birthdate: str = Form(...),
    birthtime: str = Form('12:00'),
    file: UploadFile = File(...),
    authorization: Optional[str] = Header(None)
):
    require_token(authorization)

    try:
        y,m,d = map(int, birthdate.split('-'))
    except Exception:
        raise HTTPException(status_code=400, detail='dob format YYYY-MM-DD')
    try:
        H,M = map(int, birthtime.split(':')) if ':' in birthtime else (12,0)
    except Exception:
        H,M = 12,0

    content = await file.read()
    try:
        img = Image.open(io.BytesIO(content)).convert('RGB')
    except Exception:
        raise HTTPException(status_code=400, detail='image parse fail')
    img_rgb = np.array(img)

    face_summary, face_meta = analyze_face_landmarks(img_rgb)
    saju_meta = build_saju_meta(y,m,d,H,M)
    saju_prompt = build_saju_prompt(name, gender, calendarType, birthdate, birthtime, saju_meta)
    saju_summary = call_openai_saju(saju_prompt)

    combined_summary = f"mix: day({saju_meta['day_master']}); face: {face_summary}"
    lucky = lucky_of_the_day(seed=birthdate + (birthtime or ''))

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

@app.post('/report')
def report(data: ReportIn, authorization: Optional[str] = Header(None)):
    require_token(authorization)
    pdf_bytes = build_pdf(BRAND, {'name': data.name, 'analysis': data.analysis})
    return Response(content=pdf_bytes, media_type='application/pdf',
                    headers={'Content-Disposition': f'attachment; filename=\"{data.name}_fortune_report.pdf\"'})
"@ | Set-Content -Path (Join-Path $Proj "main.py") -Encoding UTF8

# ---- Create venv with Python 3.11 ----
Push-Location $Proj
if (Test-Path ".venv") {
  Write-Host "Found old .venv. Removing to avoid conflicts..." -ForegroundColor Yellow
  Remove-Item -Recurse -Force ".venv"
}
& $py311 -m venv .venv

$venvPy = Join-Path $Proj ".venv\Scripts\python.exe"
& $venvPy -m pip install --upgrade pip
& $venvPy -m pip install -r requirements.txt

# ---- Ensure .env ----
$envPath = Join-Path $Proj ".env"
if (-not (Test-Path $envPath)) {
  Copy-Item (Join-Path $Proj ".env.example") $envPath
  notepad $envPath
}

# ---- Launch server in new window ----
Start-Process -FilePath $venvPy -ArgumentList "-m","uvicorn","main:app","--host","127.0.0.1","--port","8000","--reload"
Start-Process "http://127.0.0.1:8000/docs"
Write-Host "All set. Server is starting..." -ForegroundColor Green
Pop-Location
