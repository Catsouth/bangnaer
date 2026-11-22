#!/usr/bin/env python3
"""从用户自己的 Lige 图标包（Catsouth/lige_icon）为原生版生成服务图标。

为什么需要这个脚本：我方 GitHub 快照推送通道只收 UTF-8 文本文件，
native-app/icons/*.png 这类二进制不能进 git，所以图标改成 CI 构建时现场生成。
来源优先级：Lige 包（用户 Fork、图标全）→ 上游 appicons.py（iTunes 抓图）回退
→ 都没有时原生端运行时自动走 favicon / 首字母块（IconStore 既有逻辑）。

映射设计（键不对齐是核心问题）：
- 原生端 IconStore（Components.swift）按「预设 domain」取包内图标：
  文件必须是 icons/{preset.domain}.png（如 icons/github.com.png），
  目标清单即 Presets.swift 的 111 个预设（name + domain）。
- Lige 索引 ligeicon.json 结构为 {name, description, icons:[{name, url}]}，
  按服务名（多为英文/拼音 slug，如 wechat、jingdong）键控，url 为图标直链。
- 本脚本对每个预设依次尝试候选 slug：别名表 → 预设名 slug → appicons.json
  搜索词 → 域名首段 → 父域段；先精确名，再变体名（wechat(1) 之类，
  偏好顺序：原名 > (1) > 其余最短）。命中即下载并按 {domain}.png 落盘。
- 没命中的预设，把它在 appicons.json 里的条目写进 --missing-json，
  供 CI 下一步用上游 appicons.py 在临时目录里只补这批（回退路径）。

依赖：仅 Python 标准库（urllib）。macOS 上若有 sips，会把图标缩到 192×192
（与上游 appicons.py 产物规格一致）；没有 sips 就原图落盘（IconStore 解码时
自带降采样，功能不受影响）。

用法（仓库根目录执行，CI 里就是这么调的）：
    python3 native-app/tools/lige-icons.py \
        --out native-app/icons --missing-json build-lige-missing.json
自测（只下指定域名到临时目录）：
    python3 native-app/tools/lige-icons.py --index ~/workspace/lige-icon/ligeicon.json \
        --out /tmp/lige-test --only github.com,weixin.qq.com,jd.com,chatgpt.com
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

LIGE_INDEX_URL = "https://raw.githubusercontent.com/Catsouth/lige_icon/main/ligeicon.json"

# 域名 → Lige slug 别名表（名字对不上的已知case，2026-11-23 对照当时索引核实；
# 索引里没有的别名会自动落空走回退，不会下错图——除非同名异物，需人工增删时留意）
ALIASES = {
    "weixin.qq.com": "wechat",        # 微信
    "work.weixin.qq.com": "wechat",   # 企业微信（无专属图标时用微信）
    "jd.com": "jingdong",             # 京东
    "pan.baidu.com": "baidunetdisk",  # 百度网盘
    "x.com": "twitter",               # X（前 Twitter）
    "douyin.com": "tiktok",           # 抖音（Lige 只有 TikTok）
    "apple.com": "apple",             # Apple ID
    "icloud.com": "apple",            # iCloud（无专属，用 Apple）
    "gemini.google.com": "gemini",
    "aliyun.com": "alicloud",         # 阿里云
    "music.163.com": "neteasemusic",  # 网易云音乐（索引无此名时自动落空）
}


def norm(s: str) -> str:
    """归一化成可比 slug：小写、去空白与常见标点（保留括号，供变体处理）。"""
    return re.sub(r"[\s\-_·:：.]", "", s.lower())


def base_name(name: str) -> str:
    """去掉尾部变体后缀：wechat(1) → wechat，chatgpt4.0 → chatgpt。"""
    n = norm(name)
    n = re.sub(r"(\([^)]*\))+$", "", n)
    n = re.sub(r"\d+(\.\d+)?$", "", n) if re.search(r"[a-z]\d", n) else n
    return n


def load_index(src: str) -> list:
    if src.startswith("http://") or src.startswith("https://"):
        req = urllib.request.Request(src, headers={"User-Agent": "bangnaer-lige-icons"})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.load(r)
    else:
        data = json.loads(Path(src).read_text(encoding="utf-8"))
    return data["icons"]


def build_lookup(icons: list):
    exact, by_base = {}, {}
    for it in icons:
        exact.setdefault(norm(it["name"]), it)
        by_base.setdefault(base_name(it["name"]), []).append(it)
    for base, lst in by_base.items():
        # 变体偏好：原名 > (1) > 其余按名长
        lst.sort(key=lambda it: (norm(it["name"]) != base,
                                 norm(it["name"]) != base + "(1)",
                                 len(it["name"])))
    return exact, by_base


def candidates(name: str, domain: str, term: str):
    out = []
    if domain in ALIASES:
        out.append(ALIASES[domain])
    out.append(re.sub(r"\s+", "", name))          # 预设名去空格（Epic Games → EpicGames）
    out.append(name)
    if term:
        out.append(term)                          # appicons.json 的 iTunes 搜索词
    labels = domain.split(".")
    out.append(labels[0])                         # 域名首段（github.com → github）
    if len(labels) > 2 and labels[-2].isalpha():
        out.append(labels[-2])                    # 父域段（mail.qq.com → qq；数字段如 163 跳过）
    seen, uniq = set(), []
    for c in out:
        k = norm(c)
        if k and k not in seen:
            seen.add(k)
            uniq.append(c)
    return uniq


def find_icon(cands, exact, by_base):
    for c in cands:
        k = norm(c)
        if k in exact:
            return exact[k]
        b = base_name(c)
        if b in by_base:
            return by_base[b][0]
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="从 Lige 图标包生成原生版服务图标")
    ap.add_argument("--index", default=LIGE_INDEX_URL, help="ligeicon.json 的 URL 或本地路径")
    ap.add_argument("--presets", default="native-app/native/Presets.swift")
    ap.add_argument("--appicons", default="native-app/tools/appicons.json")
    ap.add_argument("--out", default="native-app/icons", help="图标输出目录（{domain}.png）")
    ap.add_argument("--missing-json", default=None,
                    help="把未命中预设的 appicons 条目写到这个文件，供 appicons.py 回退补图")
    ap.add_argument("--only", default=None, help="只处理这些域名（逗号分隔，自测用）")
    args = ap.parse_args()

    presets = re.findall(r'Preset\(name: "([^"]+)", domain: "([^"]+)"',
                         Path(args.presets).read_text(encoding="utf-8"))
    terms = {}
    entries = {}
    for dom, term, country in json.loads(Path(args.appicons).read_text(encoding="utf-8")):
        terms[dom] = term
        entries[dom] = [dom, term, country]
    if args.only:
        want = {d.strip() for d in args.only.split(",")}
        presets = [p for p in presets if p[1] in want]

    icons = load_index(args.index)
    exact, by_base = build_lookup(icons)
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    sips = shutil.which("sips")

    hit, miss = [], []
    for name, domain in presets:
        it = find_icon(candidates(name, domain, terms.get(domain, "")), exact, by_base)
        if it is None:
            miss.append(domain)
            print(f"MISS {domain} ({name})")
            continue
        dest = outdir / f"{domain}.png"
        try:
            req = urllib.request.Request(it["url"], headers={"User-Agent": "bangnaer-lige-icons"})
            with urllib.request.urlopen(req, timeout=30) as r:
                blob = r.read()
            if not blob.startswith(b"\x89PNG"):
                raise ValueError("not a PNG")
            dest.write_bytes(blob)
            if sips:
                subprocess.run([sips, "-s", "format", "png", "-z", "192", "192",
                                str(dest), "--out", str(dest)],
                               check=True, capture_output=True)
            hit.append(domain)
            print(f"OK   {domain} <- {it['name']}")
        except Exception as e:  # 下载失败也算未命中，交给回退
            miss.append(domain)
            print(f"FAIL {domain} <- {it['name']}: {e}")

    if args.missing_json:
        fb = [entries[d] for d in miss if d in entries]
        Path(args.missing_json).write_text(json.dumps(fb, ensure_ascii=False), encoding="utf-8")
        print(f"missing {len(miss)}（其中 {len(fb)} 条已写入 {args.missing_json} 供 appicons.py 回退）")
    print(f"lige 命中 {len(hit)}/{len(presets)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
