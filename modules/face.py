import numpy as np
from mp_optional import mp, HAS_MP
mp_face_mesh = mp.solutions.face_mesh

def analyze_face_landmarks(img_rgb):
    h, w, _ = img_rgb.shape
    with mp_face_mesh.FaceMesh(static_image_mode=True, max_num_faces=1, refine_landmarks=True) as fm:
        res = fm.process(img_rgb)
        if not res.multi_face_landmarks:
            return ('?뺣㈃ ?쇨뎬???먯??섏? 紐삵뻽?듬땲?? ?뺣㈃, 諛앹? ?섍꼍???ъ쭊??沅뚯옣?⑸땲??', {})
        lm = res.multi_face_landmarks[0]
        pts = [(int(p.x*w), int(p.y*h)) for p in lm.landmark]
    def dist(a,b): return float(np.linalg.norm(np.array(a)-np.array(b)))
    left_eye_outer, right_eye_outer = pts[33], pts[263]
    nose_tip = pts[1]
    mouth_left, mouth_right = pts[61], pts[291]
    chin, forehead = pts[199], pts[10]
    face_w = dist(left_eye_outer, right_eye_outer)
    mouth_w = dist(mouth_left, mouth_right)
    eye_center = ((left_eye_outer[0]+right_eye_outer[0])//2, (left_eye_outer[1]+right_eye_outer[1])//2)
    eye_nose = dist(eye_center, nose_tip)
    chin_forehead = dist(chin, forehead)
    ratios = {
        '?쇨뎬??: round(face_w,2),
        '?낇룺': round(mouth_w,2),
        '?덉쨷??肄붾걹': round(eye_nose,2),
        '?대쭏-??湲몄씠': round(chin_forehead,2),
        '???쇨뎬??鍮꾩쑉': round(mouth_w/max(face_w,1),3),
        '?대쭏???쇨뎬??鍮꾩쑉': round(chin_forehead/max(face_w,1),3)
    }
    summary=[]
    if ratios['???쇨뎬??鍮꾩쑉']<0.32: summary.append('?낆씠 ?곷??곸쑝濡??묒븘 ?좎쨷쨌遺꾩꽍??寃쏀뼢.')
    elif ratios['???쇨뎬??鍮꾩쑉']>0.38: summary.append('?낆씠 ?볦뼱 ?쒗쁽?Β룹궗援먯꽦??醫뗭쓬.')
    else: summary.append('?낇룺??洹좏삎?곸씠????멸?怨꾧? ?덉젙??')
    if ratios['?대쭏???쇨뎬??鍮꾩쑉']>1.6: summary.append('?몃줈 鍮꾩쑉??湲몄뼱 吏묒쨷?Β룹?援щ젰??醫뗭쓬.')
    else: summary.append('媛濡?鍮꾩쑉???곷??곸쑝濡?而??ㅼ슜?겶룻쁽??媛먭컖???곗뼱??')
    return (' '.join(summary), ratios)

