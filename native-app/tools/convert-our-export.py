#!/usr/bin/env python3
"""绑哪儿网页版导出 JSON → atlas 原生格式（整表导入）转换器。

输入：绑哪儿网页版「设置 → 导出备份」得到的 bind-backup-*.json，
      其结构就是网页版 DB 本体：
        { demo?, updatedAt,
          identities: [{id, type, value, label, createdAt?}],
          links:      [{id, identityId, name, domain, username,
                        method?, status, createdAt, rebindDone?}],
          trash?:     [{identity, links[], deletedAt} | {link, idnValue, deletedAt}] }
      身份 type 枚举：email | phone | wechat | qq | apple | google | custom
      link.method 枚举：密码登录 | Google 授权 | Apple 授权 | 微信授权 |
                        QQ 授权 | 手机号验证码 | 其它（可缺省）
      link.status 枚举：active | stopped | cancelled

输出：上游 atlas 原生 App 的整表导入格式（Store.importBackup 可直接吃）：
        { app: "atlas", version: 1, exportedAt: ISO8601,
          identities: [...], accounts: [...], deleted: {id: 毫秒时间戳} }
      对齐上游 native/Model.swift 的 Codable 结构（基线提交 9349de4 / v2.2）：
        Identity: id, type(email|phone|login), value, label, color, notes,
                  updatedAt?, order?, esim?(仅 phone 且为 true 时),
                  provider?(仅 login: wechat|apple), via?(仅 login),
                  其余未知字段进 extra 透传、写回不丢。
        Account:  id, name, domain, category, identityIds[], notes,
                  handle?, createdAt(毫秒), updatedAt?, icon?(data URL),
                  其余未知字段进 extra 透传、写回不丢。

字段映射
  身份 identities[]:
    email  -> type "email"
    phone  -> type "phone"
    wechat -> type "login", provider "wechat"
    apple  -> type "login", provider "apple"
    google -> value 像邮箱时 type "email"，否则 type "login" + provider "google"；
              原类型另存 extra.bindType="google" 以便往返还原
    qq     -> value 像邮箱时 type "email"，否则 type "login" + provider "qq"；
              原类型另存 extra.bindType="qq"
    custom / 未知类型 -> 同 google 规则，extra.bindType 存原类型
    color  -> 网页版没有此字段，按网页版 ID_META 的类型色补：
              email #5b7cff / phone #2fbf5a / wechat #07c160 /
              qq #12b7f5 / apple #8a8b93 / google #4285f4 / custom #b44fe8
    order  -> 按原数组下标写 Double，保住卡片顺序
    createdAt -> 原样保留（上游 Identity 无此已知字段，进 extra 透传，不丢）
    via    -> 网页版没有「登录卡绑在哪个邮箱/手机号上」的概念，不写（见丢失项）

  服务 links[] -> accounts[]:
    name/domain 原样；username -> handle（空则省略）
    identityId -> identityIds: [identityId]（网页版一条绑定只挂一个身份）
    createdAt 原样（同为毫秒 epoch）；缺省时用导出文件的 updatedAt，再缺省为 0
    category -> 网页版没有分类，按下方小表以域名启发式推断，推不出为「其他」
    method/status/rebindDone -> 上游 Account 没有这三个概念，写入
              extra.bindMethod / extra.bindStatus / extra.bindRebindDone，
              原生端会透传保留（往返不丢），但原生 UI 不展示（见丢失项）
    icon   -> 网页版图标是运行时按域名取的，没有存图，不写

  回收站 trash[] -> deleted 墓碑（上游只有墓碑、没有回收站）:
    {identity, links[]} -> identity.id 与每条 link.id 各写一条墓碑（deletedAt）
    {link, idnValue}    -> link.id 写一条墓碑
    墓碑只防同步时旧数据复活，快照内容本身不保留（见丢失项）

已知丢失 / 降级项
  1. trash 快照内容（被删身份/服务的完整字段）不保留，只转墓碑时间戳；
     原生端没有回收站，无法恢复。
  2. link 的 method/status/rebindDone 只进 extra 透传：原生端的服务列表
     不区分「密码登录/授权登录」、不显示在用/停用/注销状态，
     已注销（cancelled）的服务在原生端看起来与在用无异。
  3. google/qq/custom 身份被并入 email/login 两类：原生端身份只有
     邮箱/手机号/登录三类，provider 非 apple 的 login 卡在原生 UI 上
     按「微信」归类显示；原类型已存 extra.bindType，往返回网页版可还原。
  4. 微信/Apple 身份卡的 via（它绑在哪个邮箱/手机号上）网页版无此数据，
     转换后为空，原生端显示为未绑定上级的登录卡。
  5. 身份的 notes、手机号的 esim 网页版没有，不写。

用法：
    python3 convert-our-export.py 输入.json 输出.json
    python3 convert-our-export.py --selftest   # 用内置样本（仿网页版演示数据）自测
"""

import json
import re
import sys
from datetime import datetime, timezone

# 网页版 ID_META 的类型色（src/index.html），身份 color 缺省时按此补
TYPE_COLORS = {
    "email": "#5b7cff",
    "phone": "#2fbf5a",
    "wechat": "#07c160",
    "qq": "#12b7f5",
    "apple": "#8a8b93",
    "google": "#4285f4",
    "custom": "#b44fe8",
}

# 分类启发式小表（上游 CATS: 社交/购物/支付金融/开发/AI/娱乐/游戏/出行/工具/加密/其他）
# 网页版没有分类字段，这里只按域名认常见服务，认不出统一「其他」，
# 导入原生端后可用预设点选重新归类。
DOMAIN_CATEGORY = {
    "github.com": "开发",
    "zhihu.com": "社交",
    "weixin.qq.com": "社交",
    "renren.com": "社交",
    "alipay.com": "支付金融",
    "meituan.com": "出行",
    "12306.cn": "出行",
    "music.163.com": "娱乐",
    "weread.qq.com": "娱乐",
    "youtube.com": "娱乐",
    "openai.com": "AI",
    "chatgpt.com": "AI",
}

EMAIL_RE = re.compile(r"^[\w.+-]+@[\w-]+(\.[\w-]+)+$")


def convert_identity(src, index):
    """网页版 identity -> atlas Identity（dict）。"""
    t = src.get("type") or "custom"
    value = src.get("value") or ""
    out = {"id": src["id"], "value": value, "label": src.get("label") or "",
           "color": TYPE_COLORS.get(t, TYPE_COLORS["custom"]), "notes": "",
           "order": float(index)}
    if src.get("createdAt") is not None:
        out["createdAt"] = src["createdAt"]  # 上游无此已知字段，进 extra 透传
    if t == "email":
        out["type"] = "email"
    elif t == "phone":
        out["type"] = "phone"
    elif t == "wechat":
        out["type"] = "login"
        out["provider"] = "wechat"
    elif t == "apple":
        out["type"] = "login"
        out["provider"] = "apple"
    else:  # google / qq / custom / 未知类型：并入 email 或 login，原类型存 bindType
        out["bindType"] = t
        if EMAIL_RE.match(value):
            out["type"] = "email"
        else:
            out["type"] = "login"
            out["provider"] = t
    return out


def convert_link(src, fallback_ts):
    """网页版 link -> atlas Account（dict）。"""
    out = {
        "id": src["id"],
        "name": src.get("name") or "?",
        "domain": src.get("domain") or "",
        "category": DOMAIN_CATEGORY.get(src.get("domain") or "", "其他"),
        "identityIds": [src["identityId"]] if src.get("identityId") else [],
        "notes": "",
        "createdAt": src.get("createdAt") or fallback_ts or 0,
    }
    if src.get("username"):
        out["handle"] = src["username"]
    if src.get("method"):
        out["bindMethod"] = src["method"]
    if src.get("status"):
        out["bindStatus"] = src["status"]
    if src.get("rebindDone"):
        out["bindRebindDone"] = True
    return out


def convert(data):
    """整表转换。返回 (输出 dict, 统计 dict)。"""
    identities_in = data.get("identities") or []
    links_in = data.get("links") or []
    trash_in = data.get("trash") or []
    fallback_ts = data.get("updatedAt") or 0

    identities = [convert_identity(i, n) for n, i in enumerate(identities_in)]
    accounts = [convert_link(l, fallback_ts) for l in links_in]

    deleted = {}
    trash_skipped = 0
    for entry in trash_in:
        ts = entry.get("deletedAt") or fallback_ts or 0
        if entry.get("identity"):
            deleted[entry["identity"]["id"]] = ts
            for l in entry.get("links") or []:
                if l.get("id"):
                    deleted[l["id"]] = ts
        elif entry.get("link"):
            deleted[entry["link"]["id"]] = ts
        else:
            trash_skipped += 1

    known_ids = {i["id"] for i in identities_in}
    dangling = sum(1 for a in accounts for x in a["identityIds"] if x not in known_ids)

    out = {
        "app": "atlas",
        "version": 1,
        "exportedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "identities": identities,
        "accounts": accounts,
        "deleted": deleted,
    }
    if data.get("demo"):
        out["demo"] = True

    stats = {
        "identities_in": len(identities_in),
        "identities_out": len(identities),
        "links_in": len(links_in),
        "accounts_out": len(accounts),
        "bindings_in": sum(1 for l in links_in if l.get("identityId")),
        "bindings_out": sum(len(a["identityIds"]) for a in accounts),
        "tombstones": len(deleted),
        "trash_skipped": trash_skipped,
        "dangling_bindings": dangling,
    }
    return out, stats


# ---------------- 自测样本：仿 src/index.html buildDemoDB() 的演示数据 ----------------
# buildDemoDB 原样计数：4 身份 / 11 服务 / 11 条绑定；另加 1 条 {link} 形 trash 测墓碑。
def sample_export():
    now = 1763800000000
    D = 86400000

    def L(lid, iid, name, domain, method, status, ago):
        l = {"id": lid, "identityId": iid, "name": name, "domain": domain,
             "username": "demo_user", "status": status or "active",
             "createdAt": now - ago * D}
        if method:
            l["method"] = method
        return l

    return {
        "demo": True, "updatedAt": 0,
        "identities": [
            {"id": "demo-email", "type": "email", "value": "demo@example.com", "label": "示例 · 主力邮箱"},
            {"id": "demo-phone", "type": "phone", "value": "13800138000", "label": "示例 · 主力号码"},
            {"id": "demo-wechat", "type": "wechat", "value": "demo_wechat", "label": "示例微信"},
            {"id": "demo-google", "type": "google", "value": "demo@gmail.com", "label": "示例 · 授权专用"},
        ],
        "links": [
            L("demo-l1", "demo-email", "GitHub", "github.com", "密码登录", "active", 1),
            L("demo-l2", "demo-email", "网易云音乐", "music.163.com", "密码登录", "active", 2),
            L("demo-l3", "demo-email", "知乎", "zhihu.com", None, "active", 3),
            L("demo-l4", "demo-phone", "微信", "weixin.qq.com", "手机号验证码", "active", 1),
            L("demo-l5", "demo-phone", "支付宝", "alipay.com", "密码登录", "active", 3),
            L("demo-l6", "demo-phone", "美团", "meituan.com", "手机号验证码", "active", 4),
            L("demo-l7", "demo-phone", "12306", "12306.cn", "密码登录", "active", 5),
            L("demo-l8", "demo-phone", "人人网", "renren.com", "密码登录", "cancelled", 6),
            L("demo-l9", "demo-wechat", "微信读书", "weread.qq.com", "微信授权", "active", 2),
            L("demo-l10", "demo-google", "YouTube", "youtube.com", "Google 授权", "active", 3),
            L("demo-l11", "demo-google", "ChatGPT", "openai.com", "Google 授权", "active", 6),
        ],
        "trash": [
            {"link": {"id": "demo-lx", "identityId": "demo-email", "name": "旧服务",
                      "domain": "old.example.com", "username": "demo_user",
                      "status": "cancelled", "createdAt": now - 9 * D},
             "idnValue": "demo@example.com", "deletedAt": now - 1 * D},
        ],
    }


def selftest():
    src = sample_export()
    out, stats = convert(src)
    # 输出必须能被 json 往返解析（模拟原生端 JSONDecoder 读入前的最基本校验）
    out = json.loads(json.dumps(out, ensure_ascii=False))

    expect = {"identities": 4, "accounts": 11, "bindings": 11, "tombstones": 1}
    got = {"identities": stats["identities_out"], "accounts": stats["accounts_out"],
           "bindings": stats["bindings_out"], "tombstones": stats["tombstones"]}
    ok = True
    for k, v in expect.items():
        mark = "OK " if got[k] == v else "FAIL"
        if got[k] != v:
            ok = False
        print(f"  [{mark}] {k}: 期望 {v}，实际 {got[k]}")

    by_id = {i["id"]: i for i in out["identities"]}
    checks = [
        ("wechat 身份转 login+provider", by_id["demo-wechat"]["type"] == "login"
         and by_id["demo-wechat"].get("provider") == "wechat"),
        ("google(邮箱值) 身份转 email 且 bindType 留痕",
         by_id["demo-google"]["type"] == "email"
         and by_id["demo-google"].get("bindType") == "google"),
        ("username 落到 handle",
         all(a.get("handle") == "demo_user" for a in out["accounts"])),
        ("method 进 extra(bindMethod)",
         {a["id"]: a for a in out["accounts"]}["demo-l1"].get("bindMethod") == "密码登录"),
        ("无 method 的服务不写 bindMethod",
         "bindMethod" not in {a["id"]: a for a in out["accounts"]}["demo-l3"]),
        ("cancelled 状态进 extra(bindStatus)",
         {a["id"]: a for a in out["accounts"]}["demo-l8"].get("bindStatus") == "cancelled"),
        ("trash 转墓碑", out["deleted"].get("demo-lx") == src["trash"][0]["deletedAt"]),
        ("demo 标记保留", out.get("demo") is True),
        ("整表头 app/version", out["app"] == "atlas" and out["version"] == 1),
    ]
    for name, passed in checks:
        print(f"  [{'OK ' if passed else 'FAIL'}] {name}")
        ok = ok and passed

    print("自测结论：" + ("全部通过" if ok else "有失败项"))
    return 0 if ok else 1


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) != 3:
        print(__doc__.splitlines()[0])
        print("用法: convert-our-export.py 输入.json 输出.json | --selftest")
        return 2
    with open(argv[1], encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data.get("identities"), list) or not isinstance(data.get("links"), list):
        print("输入不像绑哪儿网页版导出：缺 identities/links 数组")
        return 1
    out, stats = convert(data)
    with open(argv[2], "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print("转换完成：身份 {identities_in} -> {identities_out}，"
          "服务 {links_in} -> {accounts_out}，绑定 {bindings_in} -> {bindings_out}，"
          "墓碑 {tombstones}".format(**stats))
    if stats["trash_skipped"]:
        print(f"警告：{stats['trash_skipped']} 条 trash 形状不识别，已跳过")
    if stats["dangling_bindings"]:
        print(f"警告：{stats['dangling_bindings']} 条绑定的身份 id 在身份表里找不到（已原样保留）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
