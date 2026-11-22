import SwiftUI

/// 原生手感原型的合成数据：与网页版数据互不相干，不读 localStorage。
/// 数量按用户真实规模造：邮箱身份约 127 个服务，微信 8 个、手机号 5 个；
/// 「全部」直接用邮箱那套 127 个（同量级，够验证大世界手势）。

struct ProtoService: Identifiable {
    let id: Int
    let name: String
    let domain: String
    let account: String

    var initial: String { String(name.prefix(1)) }

    /// 气泡/行图标的字母颜色：按名字确定性取色（不用 hashValue，它每次启动随机）
    var tint: Color {
        let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .red, .yellow]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

struct ProtoIdentity: Identifiable {
    let id: String
    let name: String
    let mark: String   // 核心圆里显示的字
    let value: String  // 「复制身份」用的合成身份值
}

enum ProtoData {
    static let identities: [ProtoIdentity] = [
        ProtoIdentity(id: "all", name: "全部", mark: "全", value: "all-identities"),
        ProtoIdentity(id: "email", name: "邮箱", mark: "邮", value: "demo@mail.com"),
        ProtoIdentity(id: "wechat", name: "微信", mark: "微", value: "wxid_demo"),
        ProtoIdentity(id: "phone", name: "手机号", mark: "号", value: "138****0000"),
    ]

    static func identity(_ id: String) -> ProtoIdentity {
        identities.first { $0.id == id } ?? identities[0]
    }

    static func services(for identityID: String) -> [ProtoService] {
        switch identityID {
        case "wechat":
            return [
                ("微信读书", "weread.qq.com"),
                ("微信支付", "pay.weixin.qq.com"),
                ("腾讯视频", "v.qq.com"),
                ("QQ音乐", "y.qq.com"),
                ("王者荣耀", "pvp.qq.com"),
                ("企业微信", "work.weixin.qq.com"),
                ("腾讯新闻", "news.qq.com"),
                ("微信运动", "weixin.qq.com"),
            ].enumerated().map { i, p in
                ProtoService(id: i, name: p.0, domain: p.1, account: "wxid_demo_\(i)")
            }
        case "phone":
            return [
                ("移动营业厅", "10086.cn"),
                ("联通营业厅", "10010.com"),
                ("电信营业厅", "189.cn"),
                ("交管12123", "122.gov.cn"),
                ("铁路12306", "12306.cn"),
            ].enumerated().map { i, p in
                ProtoService(id: i, name: p.0, domain: p.1, account: "1380000000\(i)")
            }
        default: // all / email：同一套 127 个
            return makePoolServices(count: 127)
        }
    }

    /// 真实服务名池（约 40 个）+ 程序生成的站点名补足到 count
    private static func makePoolServices(count: Int) -> [ProtoService] {
        let pool: [(String, String)] = [
            ("GitHub", "github.com"), ("Google", "google.com"), ("Apple", "apple.com"),
            ("Microsoft", "microsoft.com"), ("Amazon", "amazon.com"), ("Netflix", "netflix.com"),
            ("YouTube", "youtube.com"), ("X", "twitter.com"), ("Instagram", "instagram.com"),
            ("Facebook", "facebook.com"), ("Discord", "discord.com"), ("Telegram", "telegram.org"),
            ("Steam", "steampowered.com"), ("知乎", "zhihu.com"), ("微博", "weibo.com"),
            ("Bilibili", "bilibili.com"), ("抖音", "douyin.com"), ("淘宝", "taobao.com"),
            ("京东", "jd.com"), ("支付宝", "alipay.com"), ("网易云音乐", "music.163.com"),
            ("百度", "baidu.com"), ("腾讯视频", "v.qq.com"), ("小红书", "xiaohongshu.com"),
            ("滴滴", "didiglobal.com"), ("美团", "meituan.com"), ("拼多多", "pinduoduo.com"),
            ("携程", "ctrip.com"), ("豆瓣", "douban.com"), ("Notion", "notion.so"),
            ("Slack", "slack.com"), ("Zoom", "zoom.us"), ("Dropbox", "dropbox.com"),
            ("Spotify", "spotify.com"), ("Reddit", "reddit.com"), ("LinkedIn", "linkedin.com"),
            ("PayPal", "paypal.com"), ("Oracle", "oracle.com"), ("Cloudflare", "cloudflare.com"),
            ("有道云笔记", "note.youdao.com"),
        ]
        var out: [ProtoService] = []
        for i in 0..<count {
            if i < pool.count {
                out.append(ProtoService(id: i, name: pool[i].0, domain: pool[i].1,
                                        account: "user\(i)@\(pool[i].1)"))
            } else {
                let n = i - pool.count + 1
                out.append(ProtoService(id: i, name: "站点\(n)", domain: "site\(n).com",
                                        account: "user\(i)@site\(n).com"))
            }
        }
        return out
    }
}
