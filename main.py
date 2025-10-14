from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="Fortune AI Server", version="1.2.0")

SERVICE_TOKEN = os.getenv("SERVICE_TOKEN", "")
ALLOW_ORIGINS = os.getenv("ALLOW_ORIGINS", "*")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if ALLOW_ORIGINS=="*" else [o.strip() for o in ALLOW_ORIGINS.split(",")],
    allow_credentials=True, allow_methods=["*"], allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"ok": True, "version": app.version}

def check_token(h):
    if not SERVICE_TOKEN: return
    if not h or not h.lower().startswith("bearer "):
        raise HTTPException(status_code=403, detail="인증 실패: Authorization 누락")
    if h.split(" ",1)[1].strip() != SERVICE_TOKEN:
        raise HTTPException(status_code=403, detail="인증 실패: SERVICE_TOKEN 불일치")

@app.post("/analyze")
async def analyze(
    authorization: str|None = None,
    name: str = Form(...),
    gender: str = Form(...),
    calendarType: str = Form(...),
    birthdate: str = Form(...),
    birthtime: str = Form(...),
    file: UploadFile = File(...)
):
    check_token(authorization)
    content = await file.read()
    return JSONResponse({
        "ok": True,
        "meta": {"name": name,"gender": gender,"calendarType": calendarType,
                 "birthdate": birthdate,"birthtime": birthtime,"upload_kb": round(len(content)/1024,1)},
        "gwansang_summary": "서버 작동 확인용 더미 요약",
        "saju_summary": "서버 작동 확인용 더미 사주 요약",
        "combined_summary": "더미 종합 요약",
        "lucky": {"colors":["네이비","블랙","그레이"],"numbers":[3,6,9],"direction":"북"}
    })
