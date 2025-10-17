import os, json, asyncio
from typing import Dict, Any
import httpx
from lunar_python import Lunar

PRO_SAJU_URL = os.getenv("PRO_SAJU_URL", "").rstrip("/")
PRO_SAJU_KEY = os.getenv("PRO_SAJU_KEY", "")

_CACHE: dict[str, tuple[dict, float]] = {}

def _cache_get(k: str):
    v = _CACHE.get(k)
    if not v: return None
    data, exp = v
    if exp < asyncio.get_event_loop().time():
        _CACHE.pop(k, None)
        return None
    return data

def _cache_set(k: str, data: dict, ttl: int = 86400):
    _CACHE[k] = (data, asyncio.get_event_loop().time() + ttl)

def _to_solar(date_str: str, calendar_type: str) -> str:
    if calendar_type == "lunar":
        y, m, d = map(int, date_str.split("-"))
        lunar = Lunar.fromYmd(y, m, d)
        sol = lunar.getSolar()
        return f"{sol.getYear():04d}-{sol.getMonth():02d}-{sol.getDay():02d}"
    return date_str

async def fetch_saju_from_provider(meta: Dict[str, Any]) -> Dict[str, Any]:
    if not PRO_SAJU_URL or not PRO_SAJU_KEY:
        raise RuntimeError("PRO_SAJU_URL/PRO_SAJU_KEY not set")

    solar = _to_solar(meta["birthdate"], meta["calendarType"])
    hhmm  = meta.get("birthtime") or "12:00"
    if hhmm in ("紐⑤쫫","unknown"): hhmm = "12:00"

    payload = {
        "name": meta["name"],
        "gender": meta["gender"],
        "date": solar,
        "time": hhmm,
        "calendar": "solar",
    }

    ck = json.dumps(payload, sort_keys=True)
    cached = _cache_get(ck)
    if cached: return cached

    headers = {"Authorization": f"Bearer {PRO_SAJU_KEY}", "Content-Type": "application/json"}
    timeout = httpx.Timeout(3.0, connect=3.0)
    last_err = None
    for _ in (1,2):
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                r = await client.post(f"{PRO_SAJU_URL}/analyze", headers=headers, json=payload)
            r.raise_for_status()
            vendor = r.json()
            uni = adapt_vendor_to_unified(vendor, meta)
            _cache_set(ck, uni)
            return uni
        except Exception as e:
            last_err = e
            await asyncio.sleep(0.25)
    raise last_err

def adapt_vendor_to_unified(v: Dict[str, Any], meta: Dict[str, Any]) -> Dict[str, Any]:
    pillars = v.get("pillars", {})
    ten_gods = v.get("ten_gods", {})
    yhs = v.get("yongheeshin", [])
    daewoon = v.get("daewoon", [])
    sewoon = v.get("sewoon", [])
    summary = v.get("summary") or f"{meta['name']}?섏쓽 ?듭떖 ?깊뼢 諛??댁꽭 ?먮쫫 ?붿빟"

    return {
        "ok": True,
        "meta": meta,
        "saju": {
            "pillars": {
                "year": pillars.get("y"),
                "month": pillars.get("m"),
                "day": pillars.get("d"),
                "time": pillars.get("t"),
            },
            "ten_gods": ten_gods,
            "yongheeshin": yhs,
            "luck": {"daewoon": daewoon, "sewoon": sewoon},
        },
        "saju_summary": summary,
    }
