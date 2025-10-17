# -*- coding: utf-8 -*-
import os, requests

PRO_SAJU_URL = os.getenv("PRO_SAJU_URL", "").strip() or "https://vendor.example.com/v1/saju"
PRO_SAJU_KEY = os.getenv("PRO_SAJU_KEY", "").strip() or "발급받은_API_키"
PRO_AUTH_HEADER = os.getenv("PRO_SAJU_AUTH_HEADER", "").strip() or "Authorization"
PRO_AUTH_PREFIX = os.getenv("PRO_SAJU_AUTH_PREFIX", "").strip() or "Bearer "

class ProSajuError(Exception): ...

def _hdr():
    h = {"Accept":"application/json"}
    if PRO_AUTH_HEADER:
        h[PRO_AUTH_HEADER] = f"{PRO_AUTH_PREFIX}{PRO_SAJU_KEY}".strip()
    return h

def fetch_pro_saju(meta:dict)->dict:
    if not PRO_SAJU_URL or not PRO_SAJU_KEY:
        raise ProSajuError("PRO_SAJU_URL/KEY not set")

    payload = {
        "name":        meta.get("name",""),
        "gender":      meta.get("gender","unknown"),
        "calendar":    meta.get("calendarType","solar"),
        "birthdate":   meta.get("birthdate",""),
        "birthtime":   meta.get("birthtime","unknown"),
    }
    r = requests.post(PRO_SAJU_URL, json=payload, headers=_hdr(), timeout=25)
    if r.status_code != 200:
        raise ProSajuError(f"vendor http {r.status_code}: {r.text[:300]}")
    d = r.json()

    # 踰ㅻ뜑 ?묐떟 ?ㅻ? ?쒖??뺤쑝濡?留ㅽ븨 (?꾩슂???ш린留?議곗젙)
    g = d.get("face_summary") or d.get("gwansang") or ""
    s = d.get("saju_summary") or d.get("analysis") or ""
    c = d.get("combined_summary") or d.get("overall") or ""
    L = d.get("lucky") or {}

    return {
        "gwansang_summary": g,
        "saju_summary": s,
        "combined_summary": c,
        "lucky": {
            "colors": L.get("colors", []),
            "numbers": L.get("numbers", []),
            "direction": L.get("direction", ""),
        }
    }
