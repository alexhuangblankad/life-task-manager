"""把用户设计的 logo 转成各平台要的图标尺寸。

用法：python tool/make_logo.py
源图：assets/logo-source.png（用户提供的方形图，圆角外是白底）

做的事：
  1. 抠掉圆角外的白边 → 透明
  2. 生成 Windows 的 .ico（exe 图标 + 托盘图标）
  3. 生成 Android 的 mipmap（5 个密度）
  4. 生成 assets/app_icon.png（界面里「关于」和 README 用）

托盘图标的 16/24 用小图会糊成一团，所以那两个尺寸改用「中心裁切」——
放大到中间那块钟面，小图标才认得出是什么。
"""
import os
from PIL import Image, ImageDraw

ROOT = r"E:\hermes\日程软件开发"
SRC = os.path.join(ROOT, "assets", "logo-source.png")
OUT_ICON_PNG = os.path.join(ROOT, "assets", "app_icon.png")
OUT_TRAY = os.path.join(ROOT, "assets", "tray.ico")
OUT_EXE = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
ANDROID_RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

SIZES = [16, 24, 32, 48, 64, 128, 256]


def load_square() -> Image.Image:
    """读源图，裁掉四周白边，返回正方形 RGBA"""
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size

    # 白底抠成透明：从四个角泛洪填充（圆形插画外面是白的，不抠的话
    # 深色背景下圆角处会残留一圈白边）
    for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        try:
            ImageDraw.floodfill(im, corner, (0, 0, 0, 0), thresh=42)
        except Exception as e:
            print(f"  （角落 {corner} 泛洪失败，忽略：{e}）")

    # 找非白像素的边界（阈值放宽一点，避免抗锯齿的边缘被算进去）
    px = im.load()
    minx, miny, maxx, maxy = w, h, 0, 0
    step = max(1, min(w, h) // 400)
    for y in range(0, h, step):
        for x in range(0, w, step):
            r, g, b, a = px[x, y]
            if a > 30 and not (r > 244 and g > 244 and b > 244):
                if x < minx: minx = x
                if y < miny: miny = y
                if x > maxx: maxx = x
                if y > maxy: maxy = y
    if maxx <= minx or maxy <= miny:
        minx, miny, maxx, maxy = 0, 0, w, h

    box = (minx, miny, maxx + 1, maxy + 1)
    im = im.crop(box)

    # 补成正方形（居中）
    w2, h2 = im.size
    side = max(w2, h2)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - w2) // 2, (side - h2) // 2))
    return canvas


def rounded(im: Image.Image, size: int, radius_ratio: float = 0.26) -> Image.Image:
    """按目标尺寸缩放，并套一个圆角透明遮罩"""
    big = im.resize((size * 4, size * 4), Image.LANCZOS)
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big.size[0] - 1, big.size[1] - 1],
        radius=int(big.size[0] * radius_ratio),
        fill=255,
    )
    out = Image.new("RGBA", big.size, (0, 0, 0, 0))
    out.paste(big, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)


def center_crop(im: Image.Image, size: int, keep: float = 0.62) -> Image.Image:
    """取中间一块再缩放 —— 小尺寸图标用，放大主体才认得出"""
    big = im
    w, h = big.size
    cw, ch = int(w * keep), int(h * keep)
    box = ((w - cw) // 2, (h - ch) // 2, (w + cw) // 2, (h + ch) // 2)
    return rounded(big.crop(box), size, radius_ratio=0.26)


def main():
    if not os.path.exists(SRC):
        raise SystemExit(f"找不到源图：{SRC}")

    base = load_square()
    print(f"源图处理完：{base.size[0]}x{base.size[1]}（已裁白边）")

    # 1. 界面用的大图
    rounded(base, 512).save(OUT_ICON_PNG)
    print("assets/app_icon.png 512x512 ✓")

    # 2. exe 图标：所有尺寸都用完整图
    exe_frames = [rounded(base, s) for s in SIZES]
    exe_frames[-1].save(OUT_EXE, sizes=[(s, s) for s in SIZES])
    print(f"windows/runner/resources/app_icon.ico ✓（{len(SIZES)} 个尺寸）")

    # 3. 托盘图标：小尺寸用中心裁切版
    tray_frames = []
    for s in SIZES:
        tray_frames.append(center_crop(base, s) if s <= 24 else rounded(base, s))
    tray_frames[-1].save(OUT_TRAY, sizes=[(s, s) for s in SIZES])
    print(f"assets/tray.ico ✓（16/24 用中心裁切版，不然糊成一团）")

    # 4. Android mipmap
    android = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    made = 0
    for dens, size in android.items():
        d = os.path.join(ANDROID_RES, f"mipmap-{dens}")
        if os.path.isdir(d):
            rounded(base, size).save(os.path.join(d, "ic_launcher.png"))
            made += 1
    print(f"Android mipmap ✓（{made} 个密度：" + "、".join(android) + "）")


if __name__ == "__main__":
    main()
