# Renders the k-chain body and its faces into Assets.xcassets (KChainBody, KChainDevice, KChainFace*).
# Usage: python3 ios/tools/render_kchain.py <folder of the k-chain screen shots> <Assets.xcassets>
# Geometry: canvas 280 x 325 pt, screen 200 x 245 pt at (40, 40), corner 23.3 pt (KChainDeviceView matches it).
import sys, json, os, colorsys
from PIL import Image, ImageDraw, ImageFilter, ImageChops
SHOTS, OUT = sys.argv[1], sys.argv[2]
W = 660                       # 220 pt at 3x
PAD = round(W * 0.045)
SW = W - 2 * PAD
SH = round(SW * 502 / 410)
H = SH + 2 * PAD
R = round(W * 0.155)
SR = round(SW * 48 / 410)
M = 90                        # margin for the shadow
def hsl(h, s, l, a=255):
    r, g, b = colorsys.hls_to_rgb(h / 360, l / 100, s / 100)
    return (round(r * 255), round(g * 255), round(b * 255), a)
HUE = 150
def rmask(size, box, r):
    m = Image.new("L", size, 0); ImageDraw.Draw(m).rounded_rectangle(box, r, fill=255); return m
def body(face=None):
    cw, ch = W + 2 * M, H + 2 * M
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    # drop shadow
    sh = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((M + 20, M + 50, M + W - 20, M + H + 20), R, fill=(0, 0, 0, 170))
    canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(34)))
    # body gradient (160deg graphite)
    g = Image.new("RGBA", (W, H))
    px = g.load()
    stops = [(0, hsl(HUE, 6, 20)), (0.55, hsl(HUE, 8, 8)), (1, hsl(HUE, 6, 13))]
    for y in range(H):
        for x in range(W):
            t = min(1, max(0, (x * 0.34 + y * 0.94) / (W * 0.34 + H * 0.94)))
            for (a, ca), (b, cb) in zip(stops, stops[1:]):
                if a <= t <= b:
                    k = (t - a) / (b - a); px[x, y] = tuple(round(ca[i] + (cb[i] - ca[i]) * k) for i in range(4)); break
    # top-left sheen
    sheen = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse((-W * 0.3, -H * 0.5, W * 0.9, H * 0.35), fill=hsl(HUE, 6, 30, 90))
    g = Image.alpha_composite(g, sheen.filter(ImageFilter.GaussianBlur(60)))
    bm = rmask((W, H), (0, 0, W - 1, H - 1), R)
    # rim: light top edge, dark foot
    rim = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(rim)
    d.rounded_rectangle((0, 0, W - 1, H - 1), R, outline=(255, 255, 255, 26), width=3)
    top = Image.new("RGBA", (W, H), (0, 0, 0, 0)); ImageDraw.Draw(top).rounded_rectangle((0, 0, W - 1, H - 1), R, outline=(255, 255, 255, 60), width=3)
    top.putalpha(ImageChops.multiply(top.getchannel("A"), Image.linear_gradient("L").resize((W, H)).point(lambda v: 255 - v).point(lambda v: v if v > 200 else 0)))
    g = Image.alpha_composite(Image.alpha_composite(g, rim), top)
    g.putalpha(ImageChops.multiply(g.getchannel("A"), bm))
    canvas.alpha_composite(g, (M, M))
    # side keys (right edge): BOOT and PWR
    keys = ImageDraw.Draw(canvas)
    for top_, hgt in ((0.26, 0.12), (0.42, 0.07)):
        y0 = M + round(H * top_); keys.rounded_rectangle((M + W - 4, y0, M + W + 8, y0 + round(H * hgt)), 5, fill=hsl(HUE, 6, 24))
        keys.line((M + W + 7, y0 + 4, M + W + 7, y0 + round(H * hgt) - 4), fill=(255, 255, 255, 40), width=2)
    # screen: black well, face inside, or transparent hole for SwiftUI
    sbox = (M + PAD, M + PAD, M + PAD + SW, M + PAD + SH)
    smask = rmask(canvas.size, (sbox[0], sbox[1], sbox[2] - 1, sbox[3] - 1), SR)
    if face is None:
        a = canvas.getchannel("A"); canvas.putalpha(ImageChops.subtract(a, smask))
    else:
        f = Image.open(os.path.join(SHOTS, face)).convert("RGBA").resize((SW, SH), Image.LANCZOS)
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0)); layer.paste(f, sbox[:2])
        layer.putalpha(smask); canvas = Image.alpha_composite(canvas, layer)
    ImageDraw.Draw(canvas).rounded_rectangle(sbox, SR, outline=(0, 0, 0, 230), width=2)
    return canvas
def imageset(name, img, scale3=True):
    d = os.path.join(OUT, name + ".imageset"); os.makedirs(d, exist_ok=True)
    img.save(os.path.join(d, name + ".png"), optimize=True)
    json.dump({"images": [{"idiom": "universal", "filename": name + ".png", "scale": "3x"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)
imageset("KChainBody", body())
imageset("KChainDevice", body("f3-pair-with-k-hole.webp"))
for src, name in [("f3-pair-with-k-hole", "KChainFacePair"), ("a1-idle", "KChainFaceIdle"), ("a3-thinking", "KChainFaceThinking"),
                  ("f4-ready", "KChainFaceReady"), ("a6-problem", "KChainFaceProblem"), ("f2-wi-fi-from-your-phone", "KChainFaceWiFi"),
                  ("a5-asking", "KChainFaceAsking")]:
    f = Image.open(os.path.join(SHOTS, src + ".webp")).convert("RGB").resize((SW, SH), Image.LANCZOS)
    d = os.path.join(OUT, name + ".imageset"); os.makedirs(d, exist_ok=True)
    f.save(os.path.join(d, name + ".jpg"), quality=88, optimize=True)
    json.dump({"images": [{"idiom": "universal", "filename": name + ".jpg", "scale": "3x"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)
print("device", W + 2 * M, H + 2 * M, "screen", SW, SH, "pad", PAD, "margin", M, "sr", SR)
