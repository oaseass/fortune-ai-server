from fastapi import FastAPI, UploadFile, File, Form, HTTPException

# === OPENAI_VENDOR_BEGIN ===
import os, json, requests

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "").strip()
OPENAI_BASE    = os.environ.get("OPENAI_BASE", "https://api.openai.com/v1").strip()
OPENAI_MODEL   = os.environ.get("OPENAI_MODEL", "gpt-4o-mini").strip()

def _build_prompt(meta: dict, gwansang_summary: str, simple_lucky: dict) -> str:
    """
    LLM?먭쾶 以??꾨＼?꾪듃. ?ъ＜(?곗썡?쇱떆쨌?ㅽ뻾쨌?⑺씗??, 愿?곸슂吏(議댁옱?섎㈃),
    ??????몄슫 ?먮쫫, 吏곸뾽/?щЪ/???嫄닿컯, 援ъ껜???됱슫 ?ъ씤?멸퉴吏
    ?쒓뎅???꾨Ц媛 ?ㅼ쑝濡?湲멸퀬 ?뺣━??蹂닿퀬???앹꽦 ?붽뎄.
    """
    return f"""
?뱀떊? ?쒓뎅???꾨Ц 紐낅━/愿??而⑥꽕?댄듃?낅땲?? ?꾨옒 硫뷀?? ?붿빟??諛뷀깢?쇰줈,
1) ?ъ＜ ?듭떖 援ъ“(?쇨컙, ?ㅽ뻾 ?몄쨷, ?⑺씗?? ?댁꽍
2) ?깊뼢쨌媛뺤젏쨌由ъ뒪?? ?좎쓽??
3) ?щЪ/而ㅻ━????멸?怨?嫄닿컯 愿???쒖븞
4) 10?????2援ш컙) 媛쒖슂, 理쒓렐 2???몄슫 ?ъ씤??
5) 愿???ъ씤?멸? ?덉쑝硫?蹂댁셿쨌蹂댁젙 肄붾찘??
6) 援ъ껜???됱슫 ?ъ씤???됱긽쨌?レ옄쨌諛⑺뼢??硫뷀???留욊쾶 媛쒖꽑)

硫뷀?:
{json.dumps(meta, ensure_ascii=False, indent=2)}

愿?곸슂???놁쑝硫??앸왂?대룄 ??:
{gwansang_summary or "?놁쓬"}

湲곕낯 ?됱슫(?쒕쾭 ??怨꾩궛):
{json.dumps(simple_lucky, ensure_ascii=False, indent=2)}

?뺤떇:
- ?ъ＜ ?붿빟: ...
- 愿???붿빟: ...
- 醫낇빀 ?붿빟: ...
- ?됱슫 ?ъ씤??
  - ?됱긽: 3~5媛?援ъ껜 ?됱씠由??쒓?)
  - ?レ옄: 3媛?
  - 諛⑺뼢: 援ъ껜 諛⑹쐞(?? 遺곷턿??
- ??? [{"start": 2026, "end": 2035, "note":"..."}, ...]
- ?몄슫: [{"year": 2025, "note":"..."},{"year": 2026, "note":"..."}]
臾몄옣泥??쒓뎅?? ?ㅻТ?곸씠怨?怨쇱옣 ?녿뒗 ?꾨Ц媛 ?ㅼ쑝濡??먯꽭???묒꽦.
"""
def call_openai_vendor(meta: dict, gwansang_summary: str, base_lucky: dict) -> dict:
    if not OPENAI_API_KEY:
        return {}
    headers = {
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json",
    }
    prompt = _build_prompt(meta, gwansang_summary, base_lucky)
    body = {
        "model": OPENAI_MODEL,
        "messages": [
            {"role":"system","content":"?뱀떊? ?좊ː?????덈뒗 ?쒓뎅??紐낅━/愿??而⑥꽕?댄듃?낅땲??"},
            {"role":"user","content": prompt}
        ],
        "temperature": 0.6,
    }
    try:
        url = f"{OPENAI_BASE}/chat/completions"
        r = requests.post(url, headers=headers, json=body, timeout=60)
        r.raise_for_status()
        txt = r.json()["choices"][0]["message"]["content"]
        # 留ㅼ슦 媛꾨떒???뚯꽌: ?뱀뀡 ?쇰꺼濡?遺꾪빐(?ㅻТ?먯꽑 JSON 紐⑤뱶 ?ъ슜 沅뚯옣)
        out = {"raw": txt}
        # ?쇰꺼 ?ㅼ썙?쒕줈 ?섎늻湲?
        parts = {
            "saju_summary": "", "gwansang_summary": "", "combined_summary": "",
            "lucky": {"colors":[],"numbers":[],"direction":""},
            "daewoon": [], "sewoon": []
        }
        # 以??⑥쐞 ?뚯떛(珥덇컙??
        for line in txt.splitlines():
            L = line.strip()
            if L.startswith("- ?ъ＜ ?붿빟"):
                parts["section"] = "saju"
            elif L.startswith("- 愿???붿빟"):
                parts["section"] = "gwan"
            elif L.startswith("- 醫낇빀 ?붿빟"):
                parts["section"] = "comb"
            elif L.startswith("- ?됱슫 ?ъ씤??):
                parts["section"] = "lucky"
            elif L.startswith("- ???):
                parts["section"] = "dae"
            elif L.startswith("- ?몄슫"):
                parts["section"] = "se"
            else:
                sec = parts.get("section","")
                if sec=="saju": parts["saju_summary"] += L + "\n"
                elif sec=="gwan": parts["gwansang_summary"] += L + "\n"
                elif sec=="comb": parts["combined_summary"] += L + "\n"
                elif sec=="lucky":
                    if "?됱긽" in L: pass
                    elif "?レ옄" in L: pass
                    elif "諛⑺뼢" in L: pass
                elif sec=="dae": pass
                elif sec=="se": pass
        return parts
    except Exception as e:
        return {}
# === OPENAI_VENDOR_END ===
from fastapi.responses import JSONResponse

# === OPENAI_VENDOR_BEGIN ===
import os, json, requests

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "").strip()
OPENAI_BASE    = os.environ.get("OPENAI_BASE", "https://api.openai.com/v1").strip()
OPENAI_MODEL   = os.environ.get("OPENAI_MODEL", "gpt-4o-mini").strip()

def _build_prompt(meta: dict, gwansang_summary: str, simple_lucky: dict) -> str:
    """
    LLM?먭쾶 以??꾨＼?꾪듃. ?ъ＜(?곗썡?쇱떆쨌?ㅽ뻾쨌?⑺씗??, 愿?곸슂吏(議댁옱?섎㈃),
    ??????몄슫 ?먮쫫, 吏곸뾽/?щЪ/???嫄닿컯, 援ъ껜???됱슫 ?ъ씤?멸퉴吏
    ?쒓뎅???꾨Ц媛 ?ㅼ쑝濡?湲멸퀬 ?뺣━??蹂닿퀬???앹꽦 ?붽뎄.
    """
    return f"""
?뱀떊? ?쒓뎅???꾨Ц 紐낅━/愿??而⑥꽕?댄듃?낅땲?? ?꾨옒 硫뷀?? ?붿빟??諛뷀깢?쇰줈,
1) ?ъ＜ ?듭떖 援ъ“(?쇨컙, ?ㅽ뻾 ?몄쨷, ?⑺씗?? ?댁꽍
2) ?깊뼢쨌媛뺤젏쨌由ъ뒪?? ?좎쓽??
3) ?щЪ/而ㅻ━????멸?怨?嫄닿컯 愿???쒖븞
4) 10?????2援ш컙) 媛쒖슂, 理쒓렐 2???몄슫 ?ъ씤??
5) 愿???ъ씤?멸? ?덉쑝硫?蹂댁셿쨌蹂댁젙 肄붾찘??
6) 援ъ껜???됱슫 ?ъ씤???됱긽쨌?レ옄쨌諛⑺뼢??硫뷀???留욊쾶 媛쒖꽑)

硫뷀?:
{json.dumps(meta, ensure_ascii=False, indent=2)}

愿?곸슂???놁쑝硫??앸왂?대룄 ??:
{gwansang_summary or "?놁쓬"}

湲곕낯 ?됱슫(?쒕쾭 ??怨꾩궛):
{json.dumps(simple_lucky, ensure_ascii=False, indent=2)}

?뺤떇:
- ?ъ＜ ?붿빟: ...
- 愿???붿빟: ...
- 醫낇빀 ?붿빟: ...
- ?됱슫 ?ъ씤??
  - ?됱긽: 3~5媛?援ъ껜 ?됱씠由??쒓?)
  - ?レ옄: 3媛?
  - 諛⑺뼢: 援ъ껜 諛⑹쐞(?? 遺곷턿??
- ??? [{"start": 2026, "end": 2035, "note":"..."}, ...]
- ?몄슫: [{"year": 2025, "note":"..."},{"year": 2026, "note":"..."}]
臾몄옣泥??쒓뎅?? ?ㅻТ?곸씠怨?怨쇱옣 ?녿뒗 ?꾨Ц媛 ?ㅼ쑝濡??먯꽭???묒꽦.
"""
def call_openai_vendor(meta: dict, gwansang_summary: str, base_lucky: dict) -> dict:
    if not OPENAI_API_KEY:
        return {}
    headers = {
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json",
    }
    prompt = _build_prompt(meta, gwansang_summary, base_lucky)
    body = {
        "model": OPENAI_MODEL,
        "messages": [
            {"role":"system","content":"?뱀떊? ?좊ː?????덈뒗 ?쒓뎅??紐낅━/愿??而⑥꽕?댄듃?낅땲??"},
            {"role":"user","content": prompt}
        ],
        "temperature": 0.6,
    }
    try:
        url = f"{OPENAI_BASE}/chat/completions"
        r = requests.post(url, headers=headers, json=body, timeout=60)
        r.raise_for_status()
        txt = r.json()["choices"][0]["message"]["content"]
        # 留ㅼ슦 媛꾨떒???뚯꽌: ?뱀뀡 ?쇰꺼濡?遺꾪빐(?ㅻТ?먯꽑 JSON 紐⑤뱶 ?ъ슜 沅뚯옣)
        out = {"raw": txt}
        # ?쇰꺼 ?ㅼ썙?쒕줈 ?섎늻湲?
        parts = {
            "saju_summary": "", "gwansang_summary": "", "combined_summary": "",
            "lucky": {"colors":[],"numbers":[],"direction":""},
            "daewoon": [], "sewoon": []
        }
        # 以??⑥쐞 ?뚯떛(珥덇컙??
        for line in txt.splitlines():
            L = line.strip()
            if L.startswith("- ?ъ＜ ?붿빟"):
                parts["section"] = "saju"
            elif L.startswith("- 愿???붿빟"):
                parts["section"] = "gwan"
            elif L.startswith("- 醫낇빀 ?붿빟"):
                parts["section"] = "comb"
            elif L.startswith("- ?됱슫 ?ъ씤??):
                parts["section"] = "lucky"
            elif L.startswith("- ???):
                parts["section"] = "dae"
            elif L.startswith("- ?몄슫"):
                parts["section"] = "se"
            else:
                sec = parts.get("section","")
                if sec=="saju": parts["saju_summary"] += L + "\n"
                elif sec=="gwan": parts["gwansang_summary"] += L + "\n"
                elif sec=="comb": parts["combined_summary"] += L + "\n"
                elif sec=="lucky":
                    if "?됱긽" in L: pass
                    elif "?レ옄" in L: pass
                    elif "諛⑺뼢" in L: pass
                elif sec=="dae": pass
                elif sec=="se": pass
        return parts
    except Exception as e:
        return {}
# === OPENAI_VENDOR_END ===
from saju_pro_adapter import fetch_saju_from_provider
from fastapi.middleware.cors import CORSMiddleware

# === OPENAI_VENDOR_BEGIN ===
import os, json, requests

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "").strip()
OPENAI_BASE    = os.environ.get("OPENAI_BASE", "https://api.openai.com/v1").strip()
OPENAI_MODEL   = os.environ.get("OPENAI_MODEL", "gpt-4o-mini").strip()

def _build_prompt(meta: dict, gwansang_summary: str, simple_lucky: dict) -> str:
    """
    LLM?먭쾶 以??꾨＼?꾪듃. ?ъ＜(?곗썡?쇱떆쨌?ㅽ뻾쨌?⑺씗??, 愿?곸슂吏(議댁옱?섎㈃),
    ??????몄슫 ?먮쫫, 吏곸뾽/?щЪ/???嫄닿컯, 援ъ껜???됱슫 ?ъ씤?멸퉴吏
    ?쒓뎅???꾨Ц媛 ?ㅼ쑝濡?湲멸퀬 ?뺣━??蹂닿퀬???앹꽦 ?붽뎄.
    """
    return f"""
?뱀떊? ?쒓뎅???꾨Ц 紐낅━/愿??而⑥꽕?댄듃?낅땲?? ?꾨옒 硫뷀?? ?붿빟??諛뷀깢?쇰줈,
1) ?ъ＜ ?듭떖 援ъ“(?쇨컙, ?ㅽ뻾 ?몄쨷, ?⑺씗?? ?댁꽍
2) ?깊뼢쨌媛뺤젏쨌由ъ뒪?? ?좎쓽??
3) ?щЪ/而ㅻ━????멸?怨?嫄닿컯 愿???쒖븞
4) 10?????2援ш컙) 媛쒖슂, 理쒓렐 2???몄슫 ?ъ씤??
5) 愿???ъ씤?멸? ?덉쑝硫?蹂댁셿쨌蹂댁젙 肄붾찘??
6) 援ъ껜???됱슫 ?ъ씤???됱긽쨌?レ옄쨌諛⑺뼢??硫뷀???留욊쾶 媛쒖꽑)

硫뷀?:
{json.dumps(meta, ensure_ascii=False, indent=2)}

愿?곸슂???놁쑝硫??앸왂?대룄 ??:
{gwansang_summary or "?놁쓬"}

湲곕낯 ?됱슫(?쒕쾭 ??怨꾩궛):
{json.dumps(simple_lucky, ensure_ascii=False, indent=2)}

?뺤떇:
- ?ъ＜ ?붿빟: ...
- 愿???붿빟: ...
- 醫낇빀 ?붿빟: ...
- ?됱슫 ?ъ씤??
  - ?됱긽: 3~5媛?援ъ껜 ?됱씠由??쒓?)
  - ?レ옄: 3媛?
  - 諛⑺뼢: 援ъ껜 諛⑹쐞(?? 遺곷턿??
- ??? [{"start": 2026, "end": 2035, "note":"..."}, ...]
- ?몄슫: [{"year": 2025, "note":"..."},{"year": 2026, "note":"..."}]
臾몄옣泥??쒓뎅?? ?ㅻТ?곸씠怨?怨쇱옣 ?녿뒗 ?꾨Ц媛 ?ㅼ쑝濡??먯꽭???묒꽦.
"""
def call_openai_vendor(meta: dict, gwansang_summary: str, base_lucky: dict) -> dict:
    if not OPENAI_API_KEY:
        return {}
    headers = {
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json",
    }
    prompt = _build_prompt(meta, gwansang_summary, base_lucky)
    body = {
        "model": OPENAI_MODEL,
        "messages": [
            {"role":"system","content":"?뱀떊? ?좊ː?????덈뒗 ?쒓뎅??紐낅━/愿??而⑥꽕?댄듃?낅땲??"},
            {"role":"user","content": prompt}
        ],
        "temperature": 0.6,
    }
    try:
        url = f"{OPENAI_BASE}/chat/completions"
        r = requests.post(url, headers=headers, json=body, timeout=60)
        r.raise_for_status()
        txt = r.json()["choices"][0]["message"]["content"]
        # 留ㅼ슦 媛꾨떒???뚯꽌: ?뱀뀡 ?쇰꺼濡?遺꾪빐(?ㅻТ?먯꽑 JSON 紐⑤뱶 ?ъ슜 沅뚯옣)
        out = {"raw": txt}
        # ?쇰꺼 ?ㅼ썙?쒕줈 ?섎늻湲?
        parts = {
            "saju_summary": "", "gwansang_summary": "", "combined_summary": "",
            "lucky": {"colors":[],"numbers":[],"direction":""},
            "daewoon": [], "sewoon": []
        }
        # 以??⑥쐞 ?뚯떛(珥덇컙??
        for line in txt.splitlines():
            L = line.strip()
            if L.startswith("- ?ъ＜ ?붿빟"):
                parts["section"] = "saju"
            elif L.startswith("- 愿???붿빟"):
                parts["section"] = "gwan"
            elif L.startswith("- 醫낇빀 ?붿빟"):
                parts["section"] = "comb"
            elif L.startswith("- ?됱슫 ?ъ씤??):
                parts["section"] = "lucky"
            elif L.startswith("- ???):
                parts["section"] = "dae"
            elif L.startswith("- ?몄슫"):
                parts["section"] = "se"
            else:
                sec = parts.get("section","")
                if sec=="saju": parts["saju_summary"] += L + "\n"
                elif sec=="gwan": parts["gwansang_summary"] += L + "\n"
                elif sec=="comb": parts["combined_summary"] += L + "\n"
                elif sec=="lucky":
                    if "?됱긽" in L: pass
                    elif "?レ옄" in L: pass
                    elif "諛⑺뼢" in L: pass
                elif sec=="dae": pass
                elif sec=="se": pass
        return parts
    except Exception as e:
        return {}
# === OPENAI_VENDOR_END ===
from saju_pro_adapter import fetch_saju_from_provider
import os
# --- add these near the top of main.py ---
import os
from fastapi import FastAPI, Request, HTTPException, Depends, UploadFile, File, Form

# === OPENAI_VENDOR_BEGIN ===
import os, json, requests

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "").strip()
OPENAI_BASE    = os.environ.get("OPENAI_BASE", "https://api.openai.com/v1").strip()
OPENAI_MODEL   = os.environ.get("OPENAI_MODEL", "gpt-4o-mini").strip()

def _build_prompt(meta: dict, gwansang_summary: str, simple_lucky: dict) -> str:
    """
    LLM?먭쾶 以??꾨＼?꾪듃. ?ъ＜(?곗썡?쇱떆쨌?ㅽ뻾쨌?⑺씗??, 愿?곸슂吏(議댁옱?섎㈃),
    ??????몄슫 ?먮쫫, 吏곸뾽/?щЪ/???嫄닿컯, 援ъ껜???됱슫 ?ъ씤?멸퉴吏
    ?쒓뎅???꾨Ц媛 ?ㅼ쑝濡?湲멸퀬 ?뺣━??蹂닿퀬???앹꽦 ?붽뎄.
    """
    return f"""
?뱀떊? ?쒓뎅???꾨Ц 紐낅━/愿??而⑥꽕?댄듃?낅땲?? ?꾨옒 硫뷀?? ?붿빟??諛뷀깢?쇰줈,
1) ?ъ＜ ?듭떖 援ъ“(?쇨컙, ?ㅽ뻾 ?몄쨷, ?⑺씗?? ?댁꽍
2) ?깊뼢쨌媛뺤젏쨌由ъ뒪?? ?좎쓽??
3) ?щЪ/而ㅻ━????멸?怨?嫄닿컯 愿???쒖븞
4) 10?????2援ш컙) 媛쒖슂, 理쒓렐 2???몄슫 ?ъ씤??
5) 愿???ъ씤?멸? ?덉쑝硫?蹂댁셿쨌蹂댁젙 肄붾찘??
6) 援ъ껜???됱슫 ?ъ씤???됱긽쨌?レ옄쨌諛⑺뼢??硫뷀???留욊쾶 媛쒖꽑)

硫뷀?:
{json.dumps(meta, ensure_ascii=False, indent=2)}

愿?곸슂???놁쑝硫??앸왂?대룄 ??:
{gwansang_summary or "?놁쓬"}

湲곕낯 ?됱슫(?쒕쾭 ??怨꾩궛):
{json.dumps(simple_lucky, ensure_ascii=False, indent=2)}

?뺤떇:
- ?ъ＜ ?붿빟: ...
- 愿???붿빟: ...
- 醫낇빀 ?붿빟: ...
- ?됱슫 ?ъ씤??
  - ?됱긽: 3~5媛?援ъ껜 ?됱씠由??쒓?)
  - ?レ옄: 3媛?
  - 諛⑺뼢: 援ъ껜 諛⑹쐞(?? 遺곷턿??
- ??? [{"start": 2026, "end": 2035, "note":"..."}, ...]
- ?몄슫: [{"year": 2025, "note":"..."},{"year": 2026, "note":"..."}]
臾몄옣泥??쒓뎅?? ?ㅻТ?곸씠怨?怨쇱옣 ?녿뒗 ?꾨Ц媛 ?ㅼ쑝濡??먯꽭???묒꽦.
"""
def call_openai_vendor(meta: dict, gwansang_summary: str, base_lucky: dict) -> dict:
    if not OPENAI_API_KEY:
        return {}
    headers = {
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json",
    }
    prompt = _build_prompt(meta, gwansang_summary, base_lucky)
    body = {
        "model": OPENAI_MODEL,
        "messages": [
            {"role":"system","content":"?뱀떊? ?좊ː?????덈뒗 ?쒓뎅??紐낅━/愿??而⑥꽕?댄듃?낅땲??"},
            {"role":"user","content": prompt}
        ],
        "temperature": 0.6,
    }
    try:
        url = f"{OPENAI_BASE}/chat/completions"
        r = requests.post(url, headers=headers, json=body, timeout=60)
        r.raise_for_status()
        txt = r.json()["choices"][0]["message"]["content"]
        # 留ㅼ슦 媛꾨떒???뚯꽌: ?뱀뀡 ?쇰꺼濡?遺꾪빐(?ㅻТ?먯꽑 JSON 紐⑤뱶 ?ъ슜 沅뚯옣)
        out = {"raw": txt}
        # ?쇰꺼 ?ㅼ썙?쒕줈 ?섎늻湲?
        parts = {
            "saju_summary": "", "gwansang_summary": "", "combined_summary": "",
            "lucky": {"colors":[],"numbers":[],"direction":""},
            "daewoon": [], "sewoon": []
        }
        # 以??⑥쐞 ?뚯떛(珥덇컙??
        for line in txt.splitlines():
            L = line.strip()
            if L.startswith("- ?ъ＜ ?붿빟"):
                parts["section"] = "saju"
            elif L.startswith("- 愿???붿빟"):
                parts["section"] = "gwan"
            elif L.startswith("- 醫낇빀 ?붿빟"):
                parts["section"] = "comb"
            elif L.startswith("- ?됱슫 ?ъ씤??):
                parts["section"] = "lucky"
            elif L.startswith("- ???):
                parts["section"] = "dae"
            elif L.startswith("- ?몄슫"):
                parts["section"] = "se"
            else:
                sec = parts.get("section","")
                if sec=="saju": parts["saju_summary"] += L + "\n"
                elif sec=="gwan": parts["gwansang_summary"] += L + "\n"
                elif sec=="comb": parts["combined_summary"] += L + "\n"
                elif sec=="lucky":
                    if "?됱긽" in L: pass
                    elif "?レ옄" in L: pass
                    elif "諛⑺뼢" in L: pass
                elif sec=="dae": pass
                elif sec=="se": pass
        return parts
    except Exception as e:
        return {}
# === OPENAI_VENDOR_END ===
from saju_pro_adapter import fetch_saju_from_provider

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
    # >>> PRO SAJU START (method A - auto inject)
try:
    # meta ?덉쟾 ?뺣낫
    if 'meta' not in locals():
        _form = await request.form()
        meta = {
            "name": _form.get("name") or "",
            "gender": _form.get("gender") or "unknown",
            "calendarType": _form.get("calendarType") or "solar",
            "birthdate": _form.get("birthdate") or "",
            "birthtime": _form.get("birthtime") or "unknown",
        }
        # === PRO SAJU INTEGRATION (auto) ===
        saju_part = None
        try:
            saju_part = await fetch_saju_from_provider(meta)
        except Exception:
            saju_part = None  # fallback to demo    if fetch_pro_saju:
        _norm = fetch_pro_saju(meta)
        if isinstance(_norm, dict):
            gwansang_summary = locals().get('gwansang_summary', '')
            saju_summary     = locals().get('saju_summary', '')
            combined_summary = locals().get('combined_summary', '')
            lucky            = locals().get('lucky', {"colors":[],"numbers":[],"direction":""})

            if _norm.get('gwansang_summary'): gwansang_summary = _norm['gwansang_summary']
            if _norm.get('saju_summary'):     saju_summary     = _norm['saju_summary']
            if _norm.get('combined_summary'): combined_summary = _norm['combined_summary']
            if isinstance(_norm.get('lucky'), dict): lucky.update(_norm['lucky'])

            result = {
                "ok": True,
                "meta": meta,
                "gwansang_summary": gwansang_summary,
                "saju_summary": (saju_part["saju_summary"] if saju_part else "?곕え 怨꾩궛媛?(?곸뾽?⑹? ?꾨Ц ?ъ＜ API)"),
                "combined_summary": (saju_part["saju_summary"] if saju_part else "?곕え 醫낇빀 ?붿빟"),
                "bbox": locals().get("bbox", None),
                "lucky": lucky,
            }
            return JSONResponse(result) if 'JSONResponse' in globals() else result
except Exception as _e:
    print(f"[WARN] PRO block error: {_e}")
# <<< PRO SAJU END
return JSONResponse({
        "ok": True,
        "meta": {"name": name,"gender": gender,"calendarType": calendarType,
                 "birthdate": birthdate,"birthtime": birthtime,"upload_kb": round(len(content)/1024,1)},
        "gwansang_summary": "서버 작동 확인용 더미 요약",
        "saju_summary": (saju_part["saju_summary"] if saju_part else "?곕え 怨꾩궛媛?(?곸뾽?⑹? ?꾨Ц ?ъ＜ API)"),
        "combined_summary": (saju_part["saju_summary"] if saju_part else "?곕え 醫낇빀 ?붿빟"),
        "lucky": {"colors":["네이비","블랙","그레이"],"numbers":[3,6,9],"direction":"북"}
    })




