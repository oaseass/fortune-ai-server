from io import BytesIO
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import mm
from reportlab.lib import colors

def wrap_lines(text, max_chars):
    text = text or ''
    return [text[i:i+max_chars] for i in range(0, len(text), max_chars)]

def build_pdf(brand:str, payload:dict)->bytes:
    buff = BytesIO()
    c = canvas.Canvas(buff, pagesize=A4)
    W,H = A4
    def t(x,y,s,b=False,z=12): c.setFont('Helvetica-Bold' if b else 'Helvetica', z); c.drawString(x,y,s)
    c.setFillColor(colors.black)
    t(20*mm, H-20*mm, f'{brand} - AI 醫낇빀 ?댁꽭 由ы룷??, True, 16)
    c.line(20*mm, H-21*mm, W-20*mm, H-21*mm)
    y = H-35*mm
    name = payload.get('name','')
    an = payload.get('analysis',{})
    t(20*mm, y, f'?섎ː?? {name}'); y-=8*mm
    for label,key in [('?ъ＜ ?붿빟','saju_summary'),('愿???붿빟','face_summary'),('醫낇빀 ?댁꽍','combined_summary')]:
        t(20*mm,y,label,True); y-=7*mm
        for line in wrap_lines(an.get(key,''),90): t(20*mm,y,line); y-=6*mm
        y-=4*mm
    lucky = an.get('lucky',{})
    t(20*mm,y,'?됱슫 ?붿냼',True); y-=7*mm
    t(20*mm,y,f"?됱긽: {', '.join(lucky.get('color', []))} / ?レ옄: {', '.join(map(str,lucky.get('number', [])))} / 諛⑺뼢: {lucky.get('direction','')}"); y-=10*mm
    c.setFillColor(colors.grey); t(20*mm,15*mm,'??蹂?由ы룷?몃뒗 李멸퀬?⑹씠硫? 以묒슂???섏궗寃곗젙? ?꾨Ц媛? ?곸쓽?섏꽭??',False,9)
    c.showPage(); c.save()
    return buff.getvalue()

