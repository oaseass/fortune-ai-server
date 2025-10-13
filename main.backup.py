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
BRAND = os.getenv('COMPANY_BRAND','?대챸?꾨낫?뷀쉶?ъ썝')
client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None

app = FastAPI(title='Fortune AI Server PRO (lunar_python)', version='1.2.0')
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
    if SERVICE_TOKEN and token != SERVICE_TOKEN:
        raise HTTPException(status_code=403, detail='인증 실패: SERVICE_TOKEN이 일치하지 않습니다.')
    try:
        H,M = map(int, birthtime.split(':')) if ':' in birthtime else (12,0)
    except Exception:
        H,M = 12,0

    content = await file.read()
    try:
        img = Image.open(io.BytesIO(content)).convert('RGB')
    except Exception:
        raise HTTPException(status_code=400, detail='?대?吏 ?뚯떛 ?ㅽ뙣')
    img_rgb = np.array(img)

    face_summary, face_meta = analyze_face_landmarks(img_rgb)
    saju_meta = build_saju_meta(y,m,d,H,M)
    saju_prompt = build_saju_prompt(name, gender, calendarType, birthdate, birthtime, saju_meta)
    saju_summary = call_openai_saju(saju_prompt)

    combined_summary = (
        f"醫낇빀 ?댁꽍: ?쇨컙({saju_meta['day_master']}) ?깊뼢怨??쇨뎬 鍮꾩쑉 ?뱀쭠???④퍡 怨좊젮?섎㈃ 以묒슂???좏깮?먯꽌 ?좎쨷?④낵 異붿쭊?μ쓣 洹좏삎 ?덇쾶 ?곕뒗 寃껋씠 ?좊━?⑸땲?? [愿?? {face_summary}"
    )
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
async def report(data: ReportIn, authorization: Optional[str] = Header(None)):
    require_token(authorization)
    pdf_bytes = build_pdf(BRAND, {'name': data.name, 'analysis': data.analysis})
    return Response(content=pdf_bytes, media_type='application/pdf',
                    headers={'Content-Disposition': f'attachment; filename="{data.name}_fortune_report.pdf"'})




