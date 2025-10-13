from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Request
from fastapi.responses import StreamingResponse
from io import BytesIO
from PIL import Image
import os

# OpenCV fallback (mediapipe 없이도 작동)
import cv2
import numpy as np

from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from dotenv import load_dotenv

load_dotenv()
SERVICE_TOKEN = os.getenv("SERVICE_TOKEN", "")

app = FastAPI(title="Fortune AI Server PRO", version="1.2.0")

@app.get("/health")
def health():
    return {"ok": True, "version": "1.2.0"}

def _auth_check(request: Request):
    token = request.headers.get("Authorization", "").replace("Bearer ", "").strip()
    if SERVICE_TOKEN and token != SERVICE_TOKEN:
        raise HTTPException(status_code=403, detail="인증 실패: SERVICE_TOKEN이 일치하지 않습니다.")

@app.post("/analyze")
async def analyze(
    name: str = Form(...),
    gender: str = Form(...),
    calendarType: str = Form(...),
    birthdate: str = Form(...),
    birthtime: str = Form(...),
    file: UploadFile = File(...),
    request: Request = None
):
    if request is not None:
        _auth_check(request)

    # 이미지 로드
    data = await file.read()
    try:
        img = Image.open(BytesIO(data)).convert("RGB")
    except Exception:
        raise HTTPException(status_code=400, detail="업로드한 파일을 이미지로 열 수 없습니다.")

    # OpenCV 정면 얼굴 감지 (간이)
    bgr = cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    faces = face_cascade.detectMultiScale(gray, 1.2, 5)
    bbox = None
    if len(faces) > 0:
        x, y, w, h = faces[0]
        bbox = [int(x), int(y), int(w), int(h)]

    # 데모용 결과 (사주 부분은 실제 상업용 라이브러리로 교체 권장)
    result = {
        "ok": True,
        "meta": {
            "name": name,
            "gender": gender,
            "calendarType": calendarType,
            "birthdate": birthdate,
            "birthtime": birthtime,
        },
        "gwansang_summary": "OpenCV fallback: 얼굴 감지 " + ("성공" if bbox else "실패"),
        "saju_summary": "데모 계산값 (상업용은 검증된 명리 라이브러리/DB 권장)",
        "combined_summary": "데모 종합 요약",
        "bbox": bbox,
        "lucky": {"colors": ["네이비","블랙","그레이"], "numbers": [3,6,9], "direction": "북"},
    }
    return result

@app.post("/report")
async def report(
    name: str = Form(...),
    saju_summary: str = Form(...),
    gwansang_summary: str = Form(...),
    combined_summary: str = Form(...),
    file: UploadFile = File(None),
    request: Request = None
):
    if request is not None:
        _auth_check(request)

    buf = BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    c.setTitle(f"{name} 운세 리포트")

    text = c.beginText(50, 800)
    text.setFont("Helvetica", 12)
    for line in [
        f"이름: {name}",
        "",
        "[사주 요약]",
        saju_summary,
        "",
        "[관상 요약]",
        gwansang_summary,
        "",
        "[종합 요약]",
        combined_summary,
    ]:
        text.textLine(line)

    c.drawText(text)
    c.showPage()
    c.save()
    buf.seek(0)

    return StreamingResponse(
        buf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{name}_report.pdf"'}
    )
