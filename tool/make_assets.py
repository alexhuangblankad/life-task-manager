"""生成占位收款码 + 应用图标（真实收款码由用户提供后覆盖 assets/donate_qr.png）"""
from PIL import Image, ImageDraw, ImageFont
import os

OUT = r"E:\hermes\日程软件开发\assets"
os.makedirs(OUT, exist_ok=True)

FONT_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
FONT = r"C:\Windows\Fonts\msyh.ttc"


def font(size, bold=False):
    try:
        return ImageFont.truetype(FONT_BOLD if bold else FONT, size)
    except Exception:
        return ImageFont.load_default()


# ── 1. 收款码占位图（400x400，白色底，像二维码那样）──
w = h = 400
img = Image.new("RGB", (w, h), "#f5f6fa")
d = ImageDraw.Draw(img)
d.rounded_rectangle([8, 8, w - 8, h - 8], radius=18, outline="#c9cede", width=3)

# 四角定位框，让人一眼看出这是二维码位置
for (x, y) in [(44, 44), (w - 104, 44), (44, h - 104)]:
    d.rectangle([x, y, x + 60, y + 60], outline="#8b93a7", width=6)
    d.rectangle([x + 16, y + 16, x + 44, y + 44], fill="#8b93a7")

d.text((w // 2, h // 2 - 36), "收款码占位", font=font(30, True), fill="#39415a", anchor="mm")
d.text((w // 2, h // 2 + 6), "把图片放到", font=font(20), fill="#6b7488", anchor="mm")
d.text((w // 2, h // 2 + 38), "assets/donate_qr.png", font=font(18, True), fill="#39415a", anchor="mm")
d.text((w // 2, h // 2 + 76), "定额 5 元", font=font(20, True), fill="#c0392b", anchor="mm")
img.save(os.path.join(OUT, "donate_qr.png"))
print("donate_qr.png 生成完毕", img.size)

# ── 2. 应用图标 / 托盘图标：深蓝圆角方块 + 沙漏 ──
def make_icon(size):
    s = size * 4  # 4x 超采样后缩小，边缘干净
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    # 底：深蓝圆角方块
    dr.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=(61, 90, 254, 255))

    # 沙漏：上下两个实心三角，腰那里连起来（留太细 16px 会断成两个图形）
    cx = s // 2
    top = int(s * 0.24)
    bot = s - top
    mid = s // 2
    half = int(s * 0.19)
    waist = max(3, int(s * 0.05))      # 腰的粗细
    bar = max(4, int(s * 0.055))       # 上下两条横梁的粗细

    dr.polygon(
        [(cx - half, top), (cx + half, top), (cx + waist, mid + waist), (cx - waist, mid + waist)],
        fill=(255, 255, 255, 255),
    )
    dr.polygon(
        [(cx - half, bot), (cx + half, bot), (cx + waist, mid - waist), (cx - waist, mid - waist)],
        fill=(255, 255, 255, 255),
    )
    # 上下横梁
    dr.rectangle([cx - half - bar // 2, top - bar // 2, cx + half + bar // 2, top + bar // 2], fill=(255, 255, 255, 255))
    dr.rectangle([cx - half - bar // 2, bot - bar // 2, cx + half + bar // 2, bot + bar // 2], fill=(255, 255, 255, 255))

    return im.resize((size, size), Image.LANCZOS)


SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
icon = make_icon(256)
icon.save(os.path.join(OUT, "tray.ico"), sizes=SIZES)
icon.save(os.path.join(OUT, "app_icon.png"))

# 关键：exe / 窗口 / 任务栏用的是 windows/runner/resources/app_icon.ico，
# 不写这里的话程序图标还是 Flutter 默认那个蓝色的（用户会以为「没图标」）
EXE_ICON = r"E:\hermes\日程软件开发\windows\runner\resources\app_icon.ico"
icon.save(EXE_ICON, sizes=SIZES)
print("tray.ico / app_icon.png / windows app_icon.ico 生成完毕")
