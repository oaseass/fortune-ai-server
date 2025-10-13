#!/usr/bin/env bash
set -e
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
[ -f .env ] || cp .env.example .env
echo '[*] .env를 열어 OPENAI_API_KEY, SERVICE_TOKEN 설정 후 Enter'
read
uvicorn main:app --host 127.0.0.1 --port 8000 --reload
