try:
from mp_optional import mp, HAS_MP
HAS_MP = True
except Exception:
    mp = None
    HAS_MP = False

