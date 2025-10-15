from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import os
# --- add these near the top of main.py ---
import os
from fastapi import FastAPI, Request, HTTPException, Depends, UploadFile, File, Form

SERVICE_TOKEN = os.getenv("SERVICE_TOKEN", "790936bcb6fbff65361948fb345b222b940336c4f61033daee54cada2e6577fe")

async def require_token(request: Request):
    token = None

    # 1) Authorization 헤더
    auth = request.headers.get("authorization") or request.headers.get("Authorization")
    if auth and auth.lower().startswith("bearer "):
        token = auth.split(None, 1)[1].strip()

    # 2) 쿼리스트링 (?token=... 또는 ?service_token=...)
    if not token:
        qp = request.query_params
        token = qp.get("token") or qp.get("service_token")

    # 3) multipart/form-data 폼 필드 (token / service_token)
    if not token:
        try:
            form = await request.form()
            token = form.get("token") or form.get("service_token")
        except Exception:
            pass

    if not token or (SERVICE_TOKEN and token != SERVICE_TOKEN):
        # SERVICE_TOKEN이 .env/Render에 비어있지 않다면 일치해야 함
        raise HTTPException(status_code=401, detail="인증 실패: SERVICE_TOKEN이 일치하지 않음")
    return True

app = FastAPI(title="Fortune AI Server", version="1.2.0")
app = FastAPI()

@app.get("/health")
async def health():
    return {"ok": True, "version": "1.2.0"}

# 기존 analyze 함수 정의를 이런 식으로 바꿉니다:
@app.post("/analyze")
async def analyze(
    ok: bool = Depends(require_token),                # ← 이 줄 추가
    name: str = Form(...),
    gender: str = Form(...),
    calendarType: str = Form(...),
    birthdate: str = Form(...),
    birthtime: str = Form(...),
    file: UploadFile = File(...)
):
    # ... 기존 분석 로직 그대로 ...
    return {"ok": True, "name": name}

SERVICE_TOKEN = os.getenv("SERVICE_TOKEN", "790936bcb6fbff65361948fb345b222b940336c4f61033daee54cada2e6577fe")
ALLOW_ORIGINS = os.getenv("ALLOW_ORIGINS", "https://dnsauddmfqhsms.mycafe24.com")
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
