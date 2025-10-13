@echo off
setlocal ENABLEDELAYEDEXPANSION
set "PROJECT_DIR=%cd%"
python --version >nul 2>&1 || (echo [ERROR] Python 미설치 & pause & exit /b 1)
if not exist ".venv" (python -m venv .venv) || (echo [ERROR] venv 실패 & pause & exit /b 1)
call .venv\Scripts\activate || (echo [ERROR] activate 실패 & pause & exit /b 1)
if not exist requirements.txt (echo [ERROR] requirements.txt 없음 & pause & exit /b 1)
pip install --upgrade pip >nul
pip install -r requirements.txt || (echo [ERROR] pip 실패 & pause & exit /b 1)
if not exist .env (
  if exist .env.example (copy .env.example .env >nul) else (
    echo OPENAI_API_KEY=sk-your-key-here>.env
    echo SERVICE_TOKEN=local-test-token>>.env
    echo COMPANY_BRAND=운명을보는회사원>>.env
  )
  notepad .env
)
start "Fortune AI Server" cmd /k ".venv\Scripts\activate && uvicorn main:app --host 127.0.0.1 --port 8000 --reload"
ping -n 6 127.0.0.1 >nul
start "" "http://127.0.0.1:8000/docs"
curl -s http://127.0.0.1:8000/health > _health.json
type _health.json
if exist test.jpg (
  for /f "tokens=1 delims==" %%A in ('findstr /R "^SERVICE_TOKEN=" ".env"') do set "%%A"
  if "!SERVICE_TOKEN!"=="" set "SERVICE_TOKEN=local-test-token"
  curl -s -X POST "http://127.0.0.1:8000/analyze" ^
    -H "Authorization: Bearer !SERVICE_TOKEN!" ^
    -F "name=테스트사용자" -F "gender=male" -F "calendarType=solar" -F "birthdate=1990-01-01" -F "birthtime=12:00" ^
    -F "file=@test.jpg" > _analyze_result.json
  echo Saved: _analyze_result.json
  notepad _analyze_result.json
)
pause
