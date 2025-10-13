@echo off
REM Fortune AI - Windows runner (ASCII/CRLF)
setlocal
python --version >nul 2>&1 || (
  echo ERROR: Python is not installed or not on PATH.
  echo Install Python 3.10+ from https://www.python.org/downloads/
  pause
  exit /b 1
)
if not exist .venv (
  python -m venv .venv
  if errorlevel 1 (
    echo ERROR: Failed to create venv.
    pause
    exit /b 1
  )
)
call .venv\Scripts\activate
if errorlevel 1 (
  echo ERROR: Failed to activate venv.
  pause
  exit /b 1
)
if not exist requirements.txt (
  echo ERROR: requirements.txt not found in current folder.
  pause
  exit /b 1
)
pip install --upgrade pip
pip install -r requirements.txt
if not exist .env (
  if exist .env.example (
    copy .env.example .env
  ) else (
    echo OPENAI_API_KEY=sk-your-key-here> .env
    echo SERVICE_TOKEN=local-test-token>> .env
    echo COMPANY_BRAND=FortuneAI>> .env
  )
  notepad .env
)
uvicorn main:app --host 127.0.0.1 --port 8000 --reload
