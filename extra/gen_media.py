# -*- coding: utf-8 -*-
"""
WorkBuddy Anime Boot - 默认素材生成器（原创，无版权素材）
================================================================
程序化生成两张默认素材，任何人 clone 后都能直接使用：

    media/wallpaper.jpg   深色氛围壁纸 (1920x1080)
    media/boot.mp4        启动动画 (1920x1080 @30fps, 6 秒, H.264)

用法:  python gen_media.py
依赖:  pillow  numpy  imageio-ffmpeg

想换成自己的素材？直接覆盖 media/ 下的同名文件即可，安装器不关心来源。
"""
import math
import os
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFont
import imageio_ffmpeg

# --------------------------------------------------------------------------
# 基础配置
# --------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                      # 仓库根目录
MEDIA = os.path.join(ROOT, "media")
os.makedirs(MEDIA, exist_ok=True)

W, H = 1920, 1080        # 分辨率（与 WorkBuddy 主窗口同比例，播放时 object-fit:cover）
FPS = 30                 # 帧率
DUR = 6.0                # 时长（秒）
NF = int(FPS * DUR)      # 总帧数
SEED = 20261016          # 固定随机种子 → 每次生成结果一致

rng = np.random.default_rng(SEED)

# 每帧复用的坐标场（float32 省内存也够精度）
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
CX, CY = W / 2.0, H / 2.0
DX, DY = xx - CX, yy - CY
DIST = np.sqrt(DX * DX + DY * DY)                 # 到中心的距离场
THETA = np.arctan2(DY, DX)                        # 极角（做旋转光带用）


def load_font(candidates, size):
    """按顺序试字体，全失败退回内置位图字体。"""
    for name in candidates:
        try:
            return ImageFont.truetype(name, size)
        except Exception:
            continue
    return ImageFont.load_default()


FONT_TITLE = load_font(
    ["C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/arial.ttf",
     "arialbd.ttf", "arial.ttf"], 84)
FONT_SUB = load_font(
    ["C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/segoeui.ttf",
     "segoeui.ttf", "arial.ttf"], 28)


# --------------------------------------------------------------------------
# 静态背景（所有帧共用一层底）
# --------------------------------------------------------------------------
def make_base():
    """中心微亮的深色径向渐变 + 左上角冷光，作为整片视频的底色。"""
    t = np.clip(DIST / math.hypot(CX, CY), 0, 1)           # 0=中心 1=边角
    c0 = np.array([16, 20, 38], np.float32)                # 中心色
    c1 = np.array([5, 6, 11], np.float32)                  # 边缘色
    img = c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]

    # 左上角的一团冷光，让画面不平衡显得"有风"
    d2 = np.sqrt((xx - W * 0.20) ** 2 + (yy - H * 0.16) ** 2)
    img += (np.exp(-(d2 / (W * 0.42)) ** 2) * 0.55)[..., None] * np.array([26, 42, 78], np.float32)
    return img


BASE = make_base()


# --------------------------------------------------------------------------
# 粒子（缓慢上浮的光点，增加纵深）
# --------------------------------------------------------------------------
PARTICLES = []
for _ in range(46):
    PARTICLES.append((
        float(rng.uniform(0, W)),          # x
        float(rng.uniform(0, H)),          # y 起始
        float(rng.uniform(6, 26)),         # 上升速度 px/s
        float(rng.uniform(1.2, 3.6)),      # 半径
        float(rng.uniform(0, 2 * math.pi)) # 相位（闪烁错开）
    ))


# --------------------------------------------------------------------------
# 视频：逐帧渲染
# --------------------------------------------------------------------------
def render_frame(i):
    t = i / FPS                                        # 当前秒数
    ramp = min(1.0, t / 0.6)                           # 前 0.6s 整体渐亮（入场）

    img = BASE.copy()

    # 1) 中心主光晕（3 秒周期呼吸）
    amp = 0.78 * (0.92 + 0.08 * math.sin(2 * math.pi * t / 3.0)) * ramp
    img += (np.exp(-(DIST / 340.0) ** 2) * amp)[..., None] * np.array([66, 88, 205], np.float32)

    # 2) 外层大光晕（氛围）
    img += (np.exp(-(DIST / 640.0) ** 2) * 0.32 * ramp)[..., None] * np.array([44, 34, 92], np.float32)

    # 3) 旋转光带 1：半径 300，6 瓣，紫粉色，顺时针
    band = np.exp(-((DIST - 300.0) / 46.0) ** 2) * \
        (0.30 + 0.70 * np.maximum(0.0, np.sin(6 * THETA - 2 * math.pi * t / 4.2)) ** 2)
    a1 = min(1.0, max(0.0, (t - 0.25) / 0.9)) * ramp   # 0.25s 后淡入
    img += (band * 0.80 * a1)[..., None] * np.array([148, 106, 248], np.float32)

    # 4) 旋转光带 2：半径 402，7 瓣，青色，逆时针（更淡更细）
    band2 = np.exp(-((DIST - 402.0) / 26.0) ** 2) * \
        (0.30 + 0.70 * np.maximum(0.0, np.sin(7 * THETA + 2 * math.pi * t / 5.5)) ** 2)
    a2 = min(1.0, max(0.0, (t - 0.45) / 1.0)) * ramp
    img += (band2 * 0.42 * a2)[..., None] * np.array([70, 186, 232], np.float32)

    # 5) 中心核（1.8Hz 脉动）
    core = np.exp(-(DIST / 52.0) ** 2) * (0.55 + 0.45 * math.sin(2 * math.pi * t * 1.8)) * ramp
    img += core[..., None] * np.array([205, 216, 255], np.float32)

    # 6) 结尾脉冲：外扩的光环（象征"进入"）
    if t > 4.9:
        k = (t - 4.9) / (DUR - 4.9)                    # 0 → 1
        R = 300.0 + 520.0 * k
        pulse = np.exp(-((DIST - R) / 58.0) ** 2) * (1 - k) * 1.5
        img += pulse[..., None] * np.array([118, 140, 255], np.float32)

    # 7) 动态细噪点（抗渐变色带 + 胶片颗粒感）
    img += rng.normal(0.0, 1.7, (H, W, 1))

    img = np.clip(img, 0, 255)
    frame = Image.fromarray(img.astype(np.uint8)).convert("RGBA")

    # 8) 粒子层
    par = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(par)
    for px, py, spd, rad, ph in PARTICLES:
        y = (py - spd * t) % (H + 80) - 40             # 上浮并循环
        x = px + 14.0 * math.sin(2 * math.pi * t / 6.0 + ph)
        flash = 0.5 + 0.5 * math.sin(2 * math.pi * t * 0.7 + ph * 3)
        alpha = int((60 + 110 * flash) * ramp)
        dr.ellipse([x - rad, y - rad, x + rad, y + rad], fill=(182, 202, 255, max(0, alpha)))
    frame = Image.alpha_composite(frame, par)

    # 9) 文字层：主标题 + 副标题（easeOut 淡入）
    txt = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    td = ImageDraw.Draw(txt)

    ta = min(1.0, max(0.0, (t - 0.80) / 1.0))          # 0.8s 起淡入
    if ta > 0:
        e = 1 - (1 - ta) ** 3                          # easeOutCubic
        td.text((CX, CY + 205 + int(24 * (1 - e))), "WorkBuddy",
                font=FONT_TITLE, fill=(255, 255, 255, int(255 * e)), anchor="mm")

    tb = min(1.0, max(0.0, (t - 1.60) / 1.0))          # 1.6s 起淡入
    if tb > 0:
        e = 1 - (1 - tb) ** 3
        td.text((CX, CY + 272), "AI Agent Workspace",
                font=FONT_SUB, fill=(170, 184, 216, int(235 * e)), anchor="mm")

    return Image.alpha_composite(frame, txt).convert("RGB")


def render_video():
    out = os.path.join(MEDIA, "boot.mp4")
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    cmd = [
        ff, "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-c:v", "libx264", "-preset", "medium", "-crf", "21",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", out,
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for i in range(NF):
        proc.stdin.write(render_frame(i).tobytes())
        if i % 30 == 0:
            print(f"  frame {i}/{NF}", flush=True)
    proc.stdin.close()
    proc.wait()
    print(f"[OK] {out}  ({os.path.getsize(out) / 1048576:.2f} MB)")


# --------------------------------------------------------------------------
# 壁纸
# --------------------------------------------------------------------------
def render_wallpaper():
    img = BASE.copy()

    # 三团柔光：紫 / 青 / 品红，错开分布
    blobs = [
        (W * 0.78, H * 0.28, W * 0.30, np.array([64, 46, 118], np.float32), 0.55),
        (W * 0.24, H * 0.76, W * 0.36, np.array([26, 64, 104], np.float32), 0.50),
        (W * 0.60, H * 0.88, W * 0.24, np.array([76, 36, 88], np.float32), 0.32),
    ]
    for bx, by, br, col, amp in blobs:
        dd = np.sqrt((xx - bx) ** 2 + (yy - by) ** 2)
        img += (np.exp(-(dd / br) ** 2) * amp)[..., None] * col

    # 轻微噪点抗色带
    img += rng.normal(0.0, 2.0, (H, W, 1))
    img = np.clip(img, 0, 255).astype(np.uint8)

    out = os.path.join(MEDIA, "wallpaper.jpg")
    Image.fromarray(img).save(out, quality=90, subsampling=1, optimize=True)
    print(f"[OK] {out}  ({os.path.getsize(out) / 1048576:.2f} MB)")


if __name__ == "__main__":
    print("== WorkBuddy Anime Boot :: 默认素材生成 ==")
    print("[1/2] 生成壁纸 ...")
    render_wallpaper()
    print("[2/2] 生成启动动画 ...")
    render_video()
    print("全部完成，素材在 media/ 目录。")
