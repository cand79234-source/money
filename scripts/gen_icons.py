#!/usr/bin/env python3
"""生成 PWA 图标：192/512 普通版 + 512 maskable 版 + apple-touch-icon。
设计：蓝紫渐变圆角方块 + 白色硬币 + ¥ 符号（与 App 主题一致）。
"""
from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
OUT = "/workspace/public"
C_TOP = (91, 140, 255)   # #5B8CFF
C_BOT = (47, 107, 255)   # #2F6BFF
C_COIN = "#2F6BFF"


def vgrad(w, h, c1, c2):
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        r = int(c1[0] + (c2[0] - c1[0]) * t)
        g = int(c1[1] + (c2[1] - c1[1]) * t)
        b = int(c1[2] + (c2[2] - c1[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b, 255)
    return img


def make_tile(maskable):
    SS = 1024
    base = vgrad(SS, SS, C_TOP, C_BOT)
    if maskable:
        img = base  # 满铺，无圆角无透明，供 maskable 裁切
        coin_r = int(SS * 0.27)
    else:
        mask = Image.new("L", (SS, SS), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, SS - 1, SS - 1], radius=int(SS * 0.22), fill=255)
        img = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
        img.paste(base, (0, 0), mask)
        coin_r = int(SS * 0.31)

    d = ImageDraw.Draw(img)
    cx = cy = SS // 2
    d.ellipse([cx - coin_r, cy - coin_r, cx + coin_r, cy + coin_r],
             fill="white", outline="white")
    f = ImageFont.truetype(FONT, int(coin_r * 1.35))
    d.text((cx, cy), "¥", font=f, fill=C_COIN, anchor="mm")
    return img


def save(img, name, size=None):
    if size:
        img = img.resize((size, size), Image.LANCZOS)
    img.save(f"{OUT}/{name}", "PNG")
    print("saved", name, img.size)


save(make_tile(False), "icon-512.png")
save(make_tile(False), "icon-192.png", 192)
save(make_tile(True), "icon-maskable-512.png")
save(make_tile(False).resize((180, 180), Image.LANCZOS), "apple-touch-icon.png")
