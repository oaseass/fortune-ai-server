@echo off
python -m venv .venv
call .venv\Scripts\activate
pip install -r requirements.txt
if not exist .env copy .env.example .env
echo.
echo [*] .env 파일을 열어 OPENAI_API_KEY와 SERVICE_TOKEN을 설정하세요.
pause
uvicorn main:app --host 127.0.0.1 --port 8000 --reload
