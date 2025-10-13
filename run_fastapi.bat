@echo off
cd /d "C:\fortune_ai_server_pro_lunar"
python -m uvicorn main:app --host 0.0.0.0 --port 8000
