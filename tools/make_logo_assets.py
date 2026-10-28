"""Extracts clean, transparent Along logo assets from the two supplied brand images.

Alpha is derived from the white-on-navy artwork (no paper texture), then tinted with the
colours sampled from the navy-on-off-white artwork. The artwork itself is never redrawn:
only the background is removed and the mask is smoothly upsampled 3x for retina crispness.
Usage: python3 -I make_logo_assets.py <navy-on-light.png> <white-on-navy.png> <AssetCatalog dir>
"""
import json, sys, os
import numpy as np
from PIL import Image

light_path, dark_path, out = sys.argv[1:4]
light = np.asarray(Image.open(light_path).convert("RGB")).astype(float)
dark = np.asarray(Image.open(dark_path).convert("RGB")).astype(float)

# --- alpha mask from white-on-navy ---
lum = dark.mean(2)
bg = lum[2, 2]
alpha = np.clip((lum - bg) / (255 - bg), 0, 1)

# --- brand colours sampled from the navy-on-light artwork ---
ll = light.mean(2)
hand_rgb = light[:, :110][ll[:, :110] < 70].mean(0)
word_rgb = light[:, 140:][ll[:, 140:] < 45].mean(0)
HAND_X = (32, 133)   # hand columns in the white-on-navy image

ys, xs = np.where(alpha > 0.3)
pad = 6
y0, y1, x0, x1 = ys.min() - pad, ys.max() + pad + 1, xs.min() - pad, xs.max() + pad + 1
alpha = alpha[y0:y1, x0:x1]
hand_cols = (HAND_X[0] - x0 - 3, HAND_X[1] - x0 + 4)

def upsample(a, s=3):
    img = Image.fromarray((a * 255).astype(np.uint8)).resize((a.shape[1] * s, a.shape[0] * s), Image.LANCZOS)
    u = np.asarray(img).astype(float) / 255
    # tighten the soft edge produced by interpolation (smoothstep around 0.5)
    t = np.clip((u - 0.25) / 0.5, 0, 1)
    return t * t * (3 - 2 * t)

def save(name, a, rgb_fn):
    h, w = a.shape
    rgba = np.zeros((h, w, 4), np.uint8)
    rgba[..., :3] = rgb_fn(h, w).astype(np.uint8)
    rgba[..., 3] = (a * 255).astype(np.uint8)
    d = os.path.join(out, name + ".imageset"); os.makedirs(d, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(os.path.join(d, name + ".png"))
    props = {"preserves-vector-representation": False}
    if name == "AlongMark": props["template-rendering-intent"] = "template"
    json.dump({"images": [{"idiom": "universal", "filename": name + ".png", "scale": "3x"}],
               "info": {"version": 1, "author": "xcode"}, "properties": props},
              open(os.path.join(d, "Contents.json"), "w"), indent=2)
    return rgba

A = upsample(alpha); s = 3
hc = (hand_cols[0] * s, hand_cols[1] * s)

def two_tone(h, w):
    rgb = np.zeros((h, w, 3)); rgb[:] = word_rgb; rgb[:, :hc[1] + 6 * s] = hand_rgb; return rgb
save("AlongLogo", A, two_tone)
save("AlongLogoWhite", A, lambda h, w: np.full((h, w, 3), 255))

# hand only
H = A[:, :hc[1] + 8 * s].copy()
H[:, hc[1] + 8 * s - 1:] = 0
ys, xs = np.where(H > 0.2)
H = H[ys.min() - 4:ys.max() + 5, max(xs.min() - 4, 0):xs.max() + 5]
save("AlongMark", H, lambda h, w: np.zeros((h, w, 3)))          # template (tinted in code)
save("AlongMarkWhite", H, lambda h, w: np.full((h, w, 3), 255))

# app icon: white hand centred on brand navy
S = 1024; navy = np.array([0x1C, 0x23, 0x43], float)
hh, hw = H.shape; scale = (S * 0.56) / max(hh, hw)
Hs = np.asarray(Image.fromarray((H * 255).astype(np.uint8)).resize((int(hw * scale), int(hh * scale)), Image.LANCZOS)).astype(float) / 255
canvas = np.tile(navy, (S, S, 1))
oy, ox = (S - Hs.shape[0]) // 2, (S - Hs.shape[1]) // 2
reg = canvas[oy:oy + Hs.shape[0], ox:ox + Hs.shape[1]]
canvas[oy:oy + Hs.shape[0], ox:ox + Hs.shape[1]] = reg * (1 - Hs[..., None]) + 255 * Hs[..., None]
d = os.path.join(out, "AppIcon.appiconset"); os.makedirs(d, exist_ok=True)
Image.fromarray(canvas.astype(np.uint8), "RGB").save(os.path.join(d, "AppIcon.png"))
json.dump({"images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon.png"}],
           "info": {"version": 1, "author": "xcode"}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)
print("hand rgb", hand_rgb.round(), "word rgb", word_rgb.round(), "logo", A.shape)
