"""抓「历史上的今天」数据，清洗后打包成 assets/history_today.json。

数据源：百度百科「历史上的今天」 https://baike.baidu.com/calendar/
（网页接口按月返回 JSON，国内可达、结构化；打包进应用后运行时不依赖网络）

用法：python fetch_history.py
"""

import json
import re
import time
import urllib.request
import os

BASE = "https://baike.baidu.com/cms/home/eventsOnHistory/{month:02d}.json"
OUT = r"E:\hermes\日程软件开发\assets\history_today.json"
PER_DAY_LIMIT = 4          # 每天最多保留几条，控制体积
DESC_LIMIT = 90            # 描述截断长度

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

TAG_RE = re.compile(r"<[^>]+>")
MULTI_WS = re.compile(r"\s+")


def clean(text: str) -> str:
    if not text:
        return ""
    # 网页描述里带 <a> 标签和 &#...; 实体，先剥标签再收空白
    text = TAG_RE.sub("", text)
    text = text.replace("&nbsp;", " ").replace("&amp;", "&").replace("&quot;", '"')
    text = MULTI_WS.sub(" ", text)
    return text.strip()


def fetch_month(month: int):
    req = urllib.request.Request(
        BASE.format(month=month),
        headers={
            "User-Agent": UA,
            "Referer": "https://baike.baidu.com/calendar/",
            "Accept": "application/json, text/plain, */*",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    days = {}
    kept = 0
    for month in range(1, 13):
        try:
            data = fetch_month(month)
        except Exception as e:
            print(f"  月份 {month} 拉取失败：{e}")
            continue
        # 返回结构：{"09": {"0928": [ {...}, ... ]}}
        for _m, per_day in data.items():
            for day_key, events in per_day.items():
                if not isinstance(events, list):
                    continue
                entries = []
                for ev in events:
                    if not isinstance(ev, dict):
                        continue
                    title = clean(ev.get("title", ""))
                    desc = clean(ev.get("desc", ""))
                    if not title and not desc:
                        continue
                    desc = desc[:DESC_LIMIT]
                    entries.append({
                        "year": clean(str(ev.get("year", ""))),
                        "type": clean(str(ev.get("type", ""))),
                        "title": title,
                        "desc": desc,
                        "link": ev.get("link", ""),
                    })
                    if len(entries) >= PER_DAY_LIMIT:
                        break
                if entries:
                    key = f"{day_key[:2]}-{day_key[2:]}"   # 0928 -> 09-28
                    days[key] = entries
                    kept += len(entries)
        print(f"  月份 {month} 完成，累计 {len(days)} 天 / {kept} 条")
        time.sleep(0.6)   # 别打太快

    payload = {
        "source": "百度百科「历史上的今天」",
        "source_url": "https://baike.baidu.com/calendar/",
        "note": "内容版权归原出处，仅作个人日历页的小趣味展示",
        "days": days,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT)
    print(f"\n写入 {OUT}\n  天数 {len(days)} / 条目 {kept} / 体积 {size/1024:.0f} KB")
    print("  缺的日子：", [f"{m:02d}-{d:02d}" for m in range(1, 13) for d in range(1, 32)
                          if d <= 31 and f"{m:02d}-{d:02d}" not in days][:12], "...")


if __name__ == "__main__":
    main()
