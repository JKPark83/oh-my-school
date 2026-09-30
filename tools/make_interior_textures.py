"""시설 안쪽 디테일 텍스처를 만든다(W10 실내 디테일).

python3 tools/make_interior_textures.py → assets/textures/*.png
만든 뒤 Studio 에 올려 PropAssets 에 id 를 적는다. 색이 흰색인 부분은 Decal.Color3 로 물든다.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
random.seed(11)


def font(size, bold=True):
    return ImageFont.truetype(FONT, size, index=6 if bold else 0)


def locker_door():
    # 문짝 위에 얹는 투명 오버레이. 문짝 색(파트 색)이 비쳐 보인다
    w, h = 256, 512
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w - 1, h - 1], outline=(0, 0, 0, 70), width=6)
    d.rectangle([10, 10, w - 11, h - 11], outline=(255, 255, 255, 60), width=3)
    for i in range(5):  # 통풍구
        y = 46 + i * 22
        d.rounded_rectangle([64, y, w - 64, y + 10], radius=5, fill=(0, 0, 0, 110))
    d.rounded_rectangle([56, 200, w - 56, 250], radius=8, fill=(255, 255, 250, 240), outline=(0, 0, 0, 80), width=3)
    d.rounded_rectangle([w - 60, 280, w - 38, 380], radius=10, fill=(60, 62, 70, 255))
    d.rounded_rectangle([w - 56, 284, w - 46, 372], radius=5, fill=(150, 152, 160, 255))
    im.save(OUT / "locker_door.png")


def cabinet():
    # 실험대 몸통 앞면: 문 둘 + 손잡이 + 위 서랍 줄. 투명 오버레이
    w, h = 512, 192
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w - 1, 44], fill=(0, 0, 0, 40))
    for x0 in (8, w // 2 + 4):
        d.rounded_rectangle([x0, 54, x0 + w // 2 - 16, h - 10], radius=8, outline=(0, 0, 0, 90), width=5)
        d.rounded_rectangle([x0 + 8, 62, x0 + w // 2 - 24, h - 18], radius=6, outline=(255, 255, 255, 50), width=3)
    for x in (w // 2 - 36, w // 2 + 20):
        d.rounded_rectangle([x, 100, x + 16, 150], radius=6, fill=(220, 222, 228, 255), outline=(0, 0, 0, 90), width=2)
    for x in (w // 4, 3 * w // 4):
        d.rounded_rectangle([x - 28, 16, x + 28, 28], radius=6, fill=(220, 222, 228, 255))
    im.save(OUT / "cabinet.png")


def reagent_shelf():
    # 시약 선반 앞면(6×5 studs). 불투명
    w, h = 480, 400
    im = Image.new("RGBA", (w, h), (112, 74, 40, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([14, 14, w - 15, h - 15], fill=(236, 228, 210, 255))
    colors = [(90, 190, 240), (250, 170, 60), (120, 210, 120), (240, 110, 150), (170, 130, 230), (250, 220, 80)]
    rows = 3
    for r in range(rows):
        y1 = 14 + (r + 1) * (h - 28) // rows
        x = 26
        while x < w - 60:
            kind = random.random()
            c = random.choice(colors)
            bw = random.randint(34, 52)
            bh = random.randint(60, 96)
            top = y1 - 10 - bh
            if kind < 0.5:  # 병
                d.rounded_rectangle([x, top + 26, x + bw, y1 - 10], radius=10, fill=(210, 235, 245, 255), outline=(90, 110, 120, 255), width=3)
                d.rounded_rectangle([x + 4, top + 26 + (bh - 26) // 3, x + bw - 4, y1 - 14], radius=8, fill=c + (255,))
                d.rectangle([x + bw // 3, top + 8, x + 2 * bw // 3, top + 28], fill=(210, 235, 245, 255), outline=(90, 110, 120, 255), width=3)
                d.rectangle([x + bw // 3 - 2, top, x + 2 * bw // 3 + 2, top + 10], fill=(80, 80, 90, 255))
            else:  # 플라스크
                cxm = x + bw // 2
                d.polygon([(cxm - 8, top + 10), (cxm + 8, top + 10), (x + bw, y1 - 10), (x, y1 - 10)], fill=(210, 235, 245, 255), outline=(90, 110, 120, 255))
                d.polygon([(x + 10, y1 - 38), (x + bw - 10, y1 - 38), (x + bw - 2, y1 - 12), (x + 2, y1 - 12)], fill=c + (255,))
            d.rectangle([x + 6, y1 - 50, x + bw - 6, y1 - 40], fill=(255, 255, 255, 230))
            x += bw + random.randint(8, 18)
        d.rectangle([14, y1 - 10, w - 15, y1 + 2], fill=(140, 96, 54, 255))
    im.save(OUT / "reagent_shelf.png")


def periodic_poster():
    w, h = 640, 400
    im = Image.new("RGBA", (w, h), (252, 250, 240, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w - 1, h - 1], outline=(70, 110, 170, 255), width=10)
    t = "원소 주기율표"
    f = font(44)
    tw = d.textlength(t, font=f)
    d.text(((w - tw) / 2, 20), t, font=f, fill=(40, 60, 100, 255))
    cols, cell = 18, 32
    x0 = (w - cols * cell) // 2
    y0 = 92
    palette = {
        "a": (250, 150, 120), "b": (250, 200, 110), "t": (150, 200, 240), "p": (170, 225, 150),
        "n": (200, 170, 240), "g": (250, 170, 200),
    }
    layout = [
        "a                g",
        "ab          pnnng",
        "ab          pppng",
        "abtttttttttppppng",
        "abtttttttttppppng",
        "abtttttttttppppng",
        "abtttttttttppppng",
    ]
    for r, line in enumerate(layout):
        line = line.ljust(18)
        for c, ch in enumerate(line[:18]):
            if ch == " ":
                continue
            x, y = x0 + c * cell, y0 + r * cell
            d.rounded_rectangle([x + 2, y + 2, x + cell - 2, y + cell - 2], radius=4, fill=palette[ch] + (255,))
    for c in range(3, 17):
        for r in (0, 1):
            x, y = x0 + c * cell, y0 + (7.5 + r) * cell
            d.rounded_rectangle([x + 2, y + 2, x + cell - 2, y + cell - 2], radius=4, fill=(240, 220, 150, 255))
    im.save(OUT / "poster_periodic.png")


def floor_tile():
    # 2×2 타일 한 장. Texture 로 반복
    s = 256
    im = Image.new("RGBA", (s, s), (196, 196, 192, 255))
    d = ImageDraw.Draw(im)
    tones = [(236, 234, 226), (214, 222, 228)]
    for i in range(2):
        for j in range(2):
            c = tones[(i + j) % 2]
            d.rectangle([i * 128 + 3, j * 128 + 3, i * 128 + 124, j * 128 + 124], fill=c + (255,))
    d.rectangle([0, 0, s - 1, s - 1], outline=(190, 190, 186, 255), width=3)
    im = im.convert("RGB")
    px = im.load()
    for _ in range(3000):  # 잔 얼룩
        x, y = random.randrange(s), random.randrange(s)
        r, g, b = px[x, y]
        k = random.randint(-8, 8)
        px[x, y] = (max(0, min(255, r + k)), max(0, min(255, g + k)), max(0, min(255, b + k)))
    im.save(OUT / "floor_tile.png")


def wainscot():
    # 벽 아랫단 띠. 흰 부분이 Decal.Color3 로 물든다. 벽 높이 전체에 늘려 붙인다(띠 = 아래 22%)
    w, h = 64, 512
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    band = int(h * 0.22)
    d.rectangle([0, h - band, w, h], fill=(255, 255, 255, 255))
    d.rectangle([0, h - band - 8, w, h - band], fill=(200, 200, 200, 255))
    d.rectangle([0, h - band - 10, w, h - band - 8], fill=(150, 150, 150, 255))
    d.rectangle([0, h - 14, w, h], fill=(120, 120, 120, 255))
    im.save(OUT / "wainscot.png")


def bulletin():
    w, h = 640, 384
    im = Image.new("RGBA", (w, h), (150, 100, 55, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([16, 16, w - 17, h - 17], fill=(206, 160, 108, 255))
    px = im.load()
    for _ in range(9000):  # 코르크 점
        x, y = random.randint(18, w - 19), random.randint(18, h - 19)
        px[x, y] = random.choice([(180, 132, 84, 255), (224, 182, 128, 255)])
    t = "우리 반 게시판"
    f = font(34)
    tw = d.textlength(t, font=f)
    d.rounded_rectangle([(w - tw) / 2 - 18, 26, (w + tw) / 2 + 18, 76], radius=12, fill=(255, 250, 235, 255))
    d.text(((w - tw) / 2, 30), t, font=f, fill=(70, 100, 160, 255))
    papers = [(255, 255, 255), (255, 240, 160), (190, 230, 255), (255, 210, 225), (200, 240, 190)]
    slots = [(40, 100), (190, 110), (340, 96), (486, 108), (70, 240), (230, 250), (400, 236)]
    for i, (x, y) in enumerate(slots):
        pw, ph = random.randint(110, 130), random.randint(100, 120)
        c = papers[i % len(papers)]
        d.rectangle([x + 4, y + 4, x + pw + 4, y + ph + 4], fill=(120, 80, 40, 120))
        d.rectangle([x, y, x + pw, y + ph], fill=c + (255,))
        cx, cy = x + pw // 2, y + ph // 2 + 6
        k = i % 4
        if k == 0:  # 해
            d.ellipse([cx - 22, cy - 22, cx + 22, cy + 22], fill=(255, 190, 40, 255))
            for a in range(8):
                ang = a * math.pi / 4
                d.line([cx + 28 * math.cos(ang), cy + 28 * math.sin(ang), cx + 40 * math.cos(ang), cy + 40 * math.sin(ang)], fill=(255, 170, 30, 255), width=5)
        elif k == 1:  # 집
            d.rectangle([cx - 28, cy - 4, cx + 28, cy + 34], fill=(240, 120, 100, 255))
            d.polygon([(cx - 36, cy - 2), (cx, cy - 34), (cx + 36, cy - 2)], fill=(90, 120, 200, 255))
            d.rectangle([cx - 8, cy + 12, cx + 8, cy + 34], fill=(120, 80, 40, 255))
        elif k == 2:  # 꽃
            for a in range(6):
                ang = a * math.pi / 3
                ex, ey = cx + 16 * math.cos(ang), cy - 8 + 16 * math.sin(ang)
                d.ellipse([ex - 11, ey - 11, ex + 11, ey + 11], fill=(250, 120, 170, 255))
            d.ellipse([cx - 9, cy - 17, cx + 9, cy + 1], fill=(255, 210, 60, 255))
            d.line([cx, cy + 2, cx, cy + 40], fill=(80, 170, 80, 255), width=5)
        else:  # 글씨 줄
            for li in range(5):
                d.line([x + 14, y + 22 + li * 18, x + pw - 14 - random.randint(0, 30), y + 22 + li * 18], fill=(90, 90, 110, 255), width=4)
        pin = random.choice([(230, 70, 70), (60, 130, 230), (60, 180, 90), (250, 190, 40)])
        d.ellipse([x + pw // 2 - 7, y - 5, x + pw // 2 + 7, y + 9], fill=pin + (255,))
    im.save(OUT / "bulletin.png")


def clock():
    s = 256
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = s / 2
    d.ellipse([4, 4, s - 5, s - 5], fill=(60, 110, 180, 255))
    d.ellipse([18, 18, s - 19, s - 19], fill=(252, 252, 248, 255))
    f = font(30)
    for n in range(1, 13):
        ang = math.radians(n * 30 - 90)
        tx, ty = c + 88 * math.cos(ang), c + 88 * math.sin(ang)
        t = str(n)
        tw = d.textlength(t, font=f)
        d.text((tx - tw / 2, ty - 20), t, font=f, fill=(40, 44, 60, 255))
    for ang_deg, length, width in ((-90 + 300, 58, 10), (-90 + 60, 84, 6)):  # 10:10
        ang = math.radians(ang_deg)
        d.line([c, c, c + length * math.cos(ang), c + length * math.sin(ang)], fill=(40, 44, 60, 255), width=width)
    d.ellipse([c - 9, c - 9, c + 9, c + 9], fill=(230, 90, 60, 255))
    im.save(OUT / "clock.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for fn in (locker_door, cabinet, reagent_shelf, periodic_poster, floor_tile, wainscot, bulletin, clock):
        fn()
        print("ok", fn.__name__)
