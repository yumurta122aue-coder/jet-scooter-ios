"""Generates the JET app icon: dark ground, lime ring, bolt."""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
BG = (8, 11, 8, 255)
LIME = (124, 252, 0, 255)

img = Image.new("RGBA", (S, S), BG)
draw = ImageDraw.Draw(img)

# subtle radial glow behind the mark
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
for r, alpha in ((420, 26), (330, 34), (250, 40)):
    gd.ellipse([S // 2 - r, S // 2 - r, S // 2 + r, S // 2 + r], fill=(124, 252, 0, alpha))
glow = glow.filter(ImageFilter.GaussianBlur(90))
img = Image.alpha_composite(img, glow)

draw = ImageDraw.Draw(img)

# outer ring
ring_r = 340
draw.ellipse(
    [S // 2 - ring_r, S // 2 - ring_r, S // 2 + ring_r, S // 2 + ring_r],
    outline=LIME, width=22,
)

# lightning bolt
bolt = [
    (556, 232),
    (378, 546),
    (486, 546),
    (452, 792),
    (648, 452),
    (532, 452),
    (576, 232),
]
draw.polygon(bolt, fill=LIME)

# soft bloom on the bolt so it reads at small sizes
bloom = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bd = ImageDraw.Draw(bloom)
bd.polygon(bolt, fill=(124, 252, 0, 120))
bloom = bloom.filter(ImageFilter.GaussianBlur(26))
img = Image.alpha_composite(img, bloom)

img.convert("RGB").save(
    r"C:\Users\Huawei\Documents\deepseek-harness\default-workspace\jet-scooter-ios\JET\Resources\Assets.xcassets\AppIcon.appiconset\icon-1024.png",
    "PNG",
)
print("icon written")
