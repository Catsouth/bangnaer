#!/usr/bin/env python3
"""从 src/icon.svg 现生成全套图标（网页图标 + iOS AppIcon）。

为什么需要这个脚本：通过 Muse 的 GitHub 通道推送只能传 UTF-8 文本文件，
所有二进制（png/ico）会被整单拒绝。所以仓库的 GitHub 快照里不放二进制图标，
改由 CI（.github/workflows/build-ipa.yml）在 macOS runner 上跑本脚本现生成。
本地发版流程不变：src/ 里现成的 png/ico 保留，build.sh 照旧用它们组装 dist。

用法：
    python3 scripts/gen-icons.py --out dist \
        --appicon ios-app/BindAtlas/Assets.xcassets/AppIcon.appiconset/icon-1024.png

    --out DIR     写网页图标到 DIR：icon-192.png / icon-512.png /
                  apple-touch-icon.png / favicon.png / favicon.ico
    --appicon F   额外写一张 1024 AppIcon 到文件 F（全出血不透明，见下）

依赖：Pillow + cairosvg（CI 里 pip install pillow cairosvg）。
渲染兜底：没有 cairosvg 时尝试系统 rsvg-convert，再没有就报错退出。

图标规格与 src/ 现有文件逐一对齐（改规格先改这里，再重跑比对）：
- icon-192.png / icon-512.png：RGBA，圆角方 + 透明底角（SVG 原样）
- favicon.png：32x32 RGBA
- favicon.ico：多尺寸打包 16/32/48/64
- apple-touch-icon.png：180x180 RGB —— iOS 不认透明，SVG 压平到深空底 #0d1130 上
- AppIcon 1024：RGB 无 alpha —— iOS 要求全出血不透明，把 SVG 的渐变底
  改成铺满整个画布（去掉圆角与内缩、白描边），其余元素原样渲染
"""

import argparse
import io
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image

MASTER = 1024           # 母版渲染边长，其余尺寸都从它缩放
TOUCH_BG = (13, 17, 48)  # #0d1130 深空底，与现有 apple-touch-icon 一致


def render_svg(svg_text: str, size: int) -> Image.Image:
    """把 SVG 文本渲染成 size x size 的 RGBA 图。优先 cairosvg，兜底 rsvg-convert。"""
    try:
        import cairosvg
        png = cairosvg.svg2png(bytestring=svg_text.encode("utf-8"),
                               output_width=size, output_height=size)
        return Image.open(io.BytesIO(png)).convert("RGBA")
    except ImportError:
        pass
    # 兜底：rsvg-convert（读 stdin、写 stdout）
    try:
        proc = subprocess.run(
            ["rsvg-convert", "-w", str(size), "-h", str(size)],
            input=svg_text.encode("utf-8"), capture_output=True, check=True)
        return Image.open(io.BytesIO(proc.stdout)).convert("RGBA")
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        raise SystemExit(
            "渲染 SVG 失败：没有 cairosvg 也没有可用的 rsvg-convert。\n"
            "先装依赖：pip install pillow cairosvg") from e


def full_bleed_svg(svg_text: str) -> str:
    """把图标 SVG 改成 AppIcon 用的全出血版：渐变底铺满画布、去圆角去白描边。"""
    out, n = re.subn(
        r'<rect x="8" y="8" width="496" height="496" rx="112" fill="url\(#bg\)"/>',
        '<rect x="0" y="0" width="512" height="512" rx="0" fill="url(#bg)"/>',
        svg_text)
    if n != 1:
        raise SystemExit("全出血改写失败：没找到图标的渐变底 rect，icon.svg 结构变了？")
    out, n = re.subn(
        r'\s*<rect x="8" y="8" width="496" height="496" rx="112" fill="none"[^/]*/>',
        '', out)
    if n != 1:
        raise SystemExit("全出血改写失败：没找到图标的白描边 rect，icon.svg 结构变了？")
    return out


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description="从 icon.svg 生成全套图标")
    ap.add_argument("--svg", default=str(root / "src" / "icon.svg"),
                    help="源 SVG（默认 src/icon.svg）")
    ap.add_argument("--out", required=True, help="网页图标输出目录")
    ap.add_argument("--appicon", default=None,
                    help="AppIcon 1024 输出文件路径（可选）")
    args = ap.parse_args()

    svg_text = Path(args.svg).read_text(encoding="utf-8")
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    master = render_svg(svg_text, MASTER)

    def save_resized(img: Image.Image, size: int, name: str) -> None:
        img.resize((size, size), Image.LANCZOS).save(outdir / name)
        print(f"  {name} ({size}x{size})")

    # 网页图标：圆角 + 透明底，SVG 原样
    save_resized(master, 192, "icon-192.png")
    save_resized(master, 512, "icon-512.png")
    save_resized(master, 32, "favicon.png")

    # apple-touch-icon：压平到深空底，RGB 无透明（与现有文件一致）
    touch = Image.new("RGB", (MASTER, MASTER), TOUCH_BG)
    touch.paste(master, (0, 0), master)
    touch.resize((180, 180), Image.LANCZOS).save(outdir / "apple-touch-icon.png")
    print("  apple-touch-icon.png (180x180, RGB on #0d1130)")

    # favicon.ico：16/32/48/64 多尺寸打包（与现有文件一致）
    master.resize((64, 64), Image.LANCZOS).save(
        outdir / "favicon.ico", format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
    print("  favicon.ico (16/32/48/64)")

    # AppIcon：全出血不透明 1024
    if args.appicon:
        app = render_svg(full_bleed_svg(svg_text), MASTER).convert("RGB")
        dest = Path(args.appicon)
        dest.parent.mkdir(parents=True, exist_ok=True)
        app.save(dest)
        print(f"  AppIcon -> {dest} (1024x1024, RGB full-bleed)")

    print("图标生成完成")
    return 0


if __name__ == "__main__":
    sys.exit(main())
