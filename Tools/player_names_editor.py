#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
EPL Viewer 球员中英文名 维护工具
================================

直接读取 / 改写 ``PlayerNames.swift`` 源文件中的 ``zhById`` / ``zhByName``
两个字典 —— 单一事实来源，可 git 跟踪、重建后存活（比在 App 里写 plist 更安全，
不会出现「源文件与运行时数据不一致」的漂移）。

解析策略：只在源码里定位两块字典字面量（按 `let zhById` / `let zhByName`
起始行 + 匹配的 `    ]` 结束行），其余代码原样保留。改完只重写这两块，
不碰其它任何字符，最小 diff。

碰撞防护：``web_name`` 可能重姓（如 Fernandes 同时是曼联 B.Fernandes 与热刺
Fernandes），``set-name`` 会先查现役名单，若命中多人则警告并要求 ``--force``。
优先用 ``set-id`` 按 FPL element id 精确修改，杜绝误赋。

依赖：仅 Python 3 标准库。

用法示例
--------
  python3 player_names_editor.py stats
  python3 player_names_editor.py list --missing
  python3 player_names_editor.py list --team MUN
  python3 player_names_editor.py list --search Fernandes
  python3 player_names_editor.py show 426
  python3 player_names_editor.py set-id 426 布鲁诺·费尔南德斯
  python3 player_names_editor.py set-name Fernandes 马特乌斯·费尔南德斯 --force
  python3 player_names_editor.py interactive
"""

import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SWIFT = os.path.normpath(
    os.path.join(
        SCRIPT_DIR, "..", "EPLViewer", "Sources", "EPLViewer", "PlayerNames.swift"
    )
)
DEFAULT_BOOTSTRAP = "/tmp/fpl_bootstrap.json"

# 8 空格缩进的字典条目
ID_OPEN = re.compile(r"(    private static let zhById: \[Int: String\] = \[)")
NAME_OPEN = re.compile(r"(    private static let zhByName: \[String: String\] = \[)")
CLOSE = re.compile(r"\n    \]")  # 4 空格缩进的闭合括号，唯一匹配块结尾


# --------------------------------------------------------------------------- #
# 加载 FPL 现役名单
# --------------------------------------------------------------------------- #
def load_bootstrap(path):
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    teams = {
        t["id"]: (t.get("short_name") or t.get("name")) for t in data.get("teams", [])
    }
    players = []
    for e in data.get("elements", []):
        pid = e.get("id")
        web = e.get("web_name") or ""
        first = e.get("first_name") or ""
        second = e.get("second_name") or ""
        full = (first + " " + second).strip()
        players.append(
            {"id": pid, "web": web, "full": full, "team": teams.get(e.get("team"))}
        )
    return players


# --------------------------------------------------------------------------- #
# 解析 Swift 源里的两块字典
# --------------------------------------------------------------------------- #
def locate_block(text, open_re):
    """返回 (span_start, span_end, block_inner_text, opening_line) 或 None。"""
    m = open_re.search(text)
    if not m:
        return None
    rest = text[m.end():]
    cm = CLOSE.search(rest)
    if not cm:
        return None
    block_inner = rest[: cm.start()]
    close_abs = m.end() + cm.end()
    return m.start(), close_abs, block_inner, m.group(1)


def parse_entries(block_inner, is_id_dict):
    """把块内文本解析成有序列表，元素为 (key, name, comment)。"""
    entries = []
    for line in block_inner.split("\n"):
        if not line.strip():
            continue
        if is_id_dict:
            mm = re.match(
                r'^\s*(\d+):\s*"((?:[^"\\]|\\.)*)"(?:\s*,\s*(//.*))?', line
            )
            if mm:
                entries.append(
                    (int(mm.group(1)), mm.group(2), (mm.group(3) or "").strip())
                )
        else:
            mm = re.match(r'^\s*"((?:[^"\\]|\\.)*)":\s*"((?:[^"\\]|\\.)*)"', line)
            if mm:
                entries.append((mm.group(1), mm.group(2), ""))
    return entries


def read_swift(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    id_block = locate_block(text, ID_OPEN)
    name_block = locate_block(text, NAME_OPEN)
    if not id_block or not name_block:
        raise SystemExit("✗ 在 %s 里找不到 zhById / zhByName 字典块" % path)
    zh_by_id = parse_entries(id_block[2], True)
    zh_by_name = parse_entries(name_block[2], False)
    return text, id_block, name_block, zh_by_id, zh_by_name


# --------------------------------------------------------------------------- #
# 重建字典块文本
# --------------------------------------------------------------------------- #
def render_id_block(opening_line, entries):
    lines = [opening_line]
    for key, name, comment in entries:
        if comment:
            lines.append('        %d: "%s",   %s' % (key, name, comment))
        else:
            lines.append('        %d: "%s",' % (key, name))
    lines.append("    ]")
    return "\n".join(lines)


def render_name_block(opening_line, entries):
    lines = [opening_line]
    for key, name, _ in entries:
        lines.append('        "%s": "%s",' % (key, name))
    lines.append("    ]")
    return "\n".join(lines)


def write_swift(path, text, id_block, name_block, id_entries, name_entries, dry_run):
    new_text = text[: id_block[0]] + render_id_block(id_block[3], id_entries)
    new_text += text[id_block[1]: name_block[0]] + render_name_block(
        name_block[3], name_entries
    )
    new_text += text[name_block[1]:]

    if dry_run:
        print("—— dry-run：不写入文件，仅预览改动后的两块字典 ——")
        print(render_id_block(id_block[3], id_entries))
        print("...")
        print(render_name_block(name_block[3], name_entries))
        return False

    # 备份到 /tmp（不污染仓库；带微秒，避免同秒多次写入互相覆盖）
    ts = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    bak = "/tmp/PlayerNames_backup_%s.swift" % ts
    shutil.copy2(path, bak)
    with open(path, "w", encoding="utf-8") as f:
        f.write(new_text)
    print("✅ 已写入 %s" % path)
    print("   备份：%s" % bak)
    return True


# --------------------------------------------------------------------------- #
# 业务视图
# --------------------------------------------------------------------------- #
def to_dict(entries):
    """entries: [(key, name, comment)] -> {key: name}"""
    return {k: n for k, n, _ in entries}


def current_zh(zh_by_id, zh_by_name, pid, web):
    by_id = to_dict(zh_by_id)
    by_name = to_dict(zh_by_name)
    if pid is not None and pid in by_id:
        return by_id[pid]
    if web in by_name:
        return by_name[web]
    return None


def cmd_stats(args):
    players = load_bootstrap(args.bootstrap)
    _, _, _, zh_by_id, zh_by_name = read_swift(args.swift)
    by_id = to_dict(zh_by_id)
    by_name = to_dict(zh_by_name)
    if players is None:
        print("⚠️  bootstrap 缺失（%s），仅统计字典条目数。" % args.bootstrap)
        print("   zhById 条目: %d" % len(by_id))
        print("   zhByName 条目: %d" % len(by_name))
        return
    total = len(players)
    covered_id = sum(1 for p in players if p["id"] in by_id)
    covered_name_only = sum(
        1 for p in players if p["id"] not in by_id and p["web"] in by_name
    )
    missing = total - covered_id - covered_name_only
    print("现役球员总数 (bootstrap): %d" % total)
    print("  按 id 命中中文: %d (%.1f%%)" % (covered_id, 100.0 * covered_id / total))
    print(
        "  仅 web_name 命中: %d (%.1f%%)"
        % (covered_name_only, 100.0 * covered_name_only / total)
    )
    print(
        "  仍未译 (回退英文): %d (%.1f%%)" % (missing, 100.0 * missing / total)
    )
    print("字典规模: zhById=%d, zhByName=%d" % (len(by_id), len(by_name)))


def cmd_list(args):
    players = load_bootstrap(args.bootstrap)
    if players is None:
        print("✗ bootstrap 缺失，无法列出现役球员。请先准备好 FPL bootstrap JSON。")
        return
    _, _, _, zh_by_id, zh_by_name = read_swift(args.swift)
    by_id = to_dict(zh_by_id)
    by_name = to_dict(zh_by_name)

    q = (args.search or "").lower()
    rows = []
    for p in players:
        zh = current_zh(zh_by_id, zh_by_name, p["id"], p["web"])
        covered = zh is not None
        if args.missing and covered:
            continue
        if args.team and (p["team"] or "").upper() != args.team.upper():
            continue
        if q and q not in (p["web"] + " " + p["full"]).lower():
            continue
        rows.append(p)
    rows.sort(key=lambda x: x["id"])

    print("%-6s %-18s %-5s %-26s %s" % ("id", "web_name", "team", "full name", "中文"))
    print("-" * 70)
    for p in rows:
        zh = current_zh(zh_by_id, zh_by_name, p["id"], p["web"]) or "—"
        print(
            "%-6s %-18s %-5s %-26s %s"
            % (p["id"], p["web"][:18], p["team"] or "", p["full"][:26], zh)
        )
    print("—— 共 %d 名 ——" % len(rows))


def cmd_show(args):
    players = load_bootstrap(args.bootstrap)
    if players is None:
        print("✗ bootstrap 缺失，无法展示球员详情。")
        return
    _, _, _, zh_by_id, zh_by_name = read_swift(args.swift)
    by_id = to_dict(zh_by_id)
    by_name = to_dict(zh_by_name)
    target = None
    for p in players:
        if p["id"] == args.id:
            target = p
            break
    if not target:
        print("✗ 现役名单里没有 id=%d 的球员。" % args.id)
        return
    zh = current_zh(zh_by_id, zh_by_name, target["id"], target["web"])
    print("FPL id      : %d" % target["id"])
    print("web_name    : %s" % target["web"])
    print("全名        : %s" % target["full"])
    print("球队        : %s" % (target["team"] or "?"))
    print("当前中文    : %s" % (zh or "—（回退英文）"))
    if target["id"] in by_id:
        print("  解析路径    : zhById[id] 命中")
    elif target["web"] in by_name:
        print("  解析路径    : zhByName[web_name] 命中")
    # 碰撞检查
    same_web = [p for p in players if p["web"] == target["web"]]
    if len(same_web) > 1:
        print("⚠️  重姓碰撞：web_name '%s' 命中 %d 人 ——" % (target["web"], len(same_web)))
        for p in same_web:
            print(
                "      id=%-5d %-5s %s"
                % (p["id"], p["team"] or "", p["full"])
            )
        print("   建议用 `set-id` 按 id 精确修改，勿用 `set-name` 误赋。")


def cmd_set_id(args):
    players = load_bootstrap(args.bootstrap)
    text, id_block, name_block, zh_by_id, zh_by_name = read_swift(args.swift)
    entries = list(zh_by_id)  # 保留顺序
    idx = {k: i for i, (k, _, _) in enumerate(entries)}
    web = ""
    team = ""
    if players is not None:
        for p in players:
            if p["id"] == args.id:
                web = p["web"]
                team = p["team"] or ""
                break
    comment = ("// %s (%s)" % (web, team)).strip() if web else ""
    if args.id in idx:
        old = entries[idx[args.id]]
        entries[idx[args.id]] = (args.id, args.name, old[2] or comment)
        print("✎ 更新 id=%d: %s → %s" % (args.id, old[1], args.name))
    else:
        entries.append((args.id, args.name, comment))
        print("＋ 新增 id=%d: %s %s" % (args.id, args.name, comment))
    write_swift(
        args.swift, text, id_block, name_block, entries, list(zh_by_name), args.dry_run
    )


def cmd_set_name(args):
    players = load_bootstrap(args.bootstrap)
    text, id_block, name_block, zh_by_id, zh_by_name = read_swift(args.swift)
    entries = list(zh_by_name)
    # 碰撞检查
    if players is not None:
        same = [p for p in players if p["web"] == args.web_name]
        if len(same) > 1:
            print(
                "⚠️  web_name '%s' 命中 %d 名现役球员："
                % (args.web_name, len(same))
            )
            for p in same:
                print("      id=%-5d %-5s %s" % (p["id"], p["team"] or "", p["full"]))
            print("    用 `set-id <id>` 精确修改可避免误赋。")
            if not args.force:
                print("✗  已中止（未加 --force）。")
                return
        elif len(same) == 0:
            print(
                "⚠️  现役名单里没有 web_name='%s' —— 这条只在回退路径生效，可能无球员命中。"
                % args.web_name
            )
    keys = {k for k, _, _ in entries}
    if args.web_name in keys:
        for i, (k, _, _) in enumerate(entries):
            if k == args.web_name:
                entries[i] = (k, args.name, "")
                break
        print("✎ 更新 web_name='%s': → %s" % (args.web_name, args.name))
    else:
        entries.append((args.web_name, args.name, ""))
        print("＋ 新增 web_name='%s': %s" % (args.web_name, args.name))
    write_swift(
        args.swift, text, id_block, name_block, list(zh_by_id), entries, args.dry_run
    )


# --------------------------------------------------------------------------- #
# 交互模式
# --------------------------------------------------------------------------- #
def cmd_interactive(args):
    print("EPL 球员中英文名 维护工具 (交互模式)。输入 ? 看帮助，quit 退出。")
    while True:
        try:
            line = input("player> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not line:
            continue
        if line in ("quit", "exit", "q"):
            break
        if line in ("?", "help", "h"):
            print("命令:")
            print("  stats                        覆盖率统计")
            print("  list [--missing] [--team MUN] [--search 词]")
            print("  show <id>                    看一名球员（含碰撞检查）")
            print("  set-id <id> <中文名>         按 FPL id 精确改/加")
            print("  set-name <web_name> <中文名> [--force]   按 web_name 改/加")
            print("  dry <上述 set 命令>          预览不写入")
            continue
        # 支持 dry 前缀
        dry = False
        parts = line.split()
        if parts[0] == "dry":
            dry = True
            parts = parts[1:]
        ns = argparse.Namespace(
            swift=args.swift,
            bootstrap=args.bootstrap,
            dry_run=dry,
            force=False,
        )
        try:
            if parts[0] == "stats":
                cmd_stats(ns)
            elif parts[0] == "list":
                ns.missing = "--missing" in parts
                ns.team = _opt(parts, "--team")
                ns.search = _opt(parts, "--search")
                cmd_list(ns)
            elif parts[0] == "show" and len(parts) > 1:
                ns.id = int(parts[1])
                cmd_show(ns)
            elif parts[0] == "set-id" and len(parts) > 2:
                ns.id = int(parts[1])
                ns.name = " ".join(parts[2:])
                cmd_set_id(ns)
            elif parts[0] == "set-name" and len(parts) > 2:
                ns.web_name = parts[1]
                ns.name = " ".join(parts[2:])
                ns.force = "--force" in parts
                cmd_set_name(ns)
            else:
                print("未知命令：%s （输入 ? 看帮助）" % line)
        except SystemExit as e:
            print(e)
        except Exception as e:  # noqa
            print("✗ 出错：%s" % e)


def _opt(parts, flag):
    if flag in parts:
        i = parts.index(flag)
        if i + 1 < len(parts):
            return parts[i + 1]
    return None


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser():
    # 主解析器用的全局选项（有正常默认值）
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--swift", default=DEFAULT_SWIFT, help="PlayerNames.swift 路径")
    common.add_argument(
        "--bootstrap", default=DEFAULT_BOOTSTRAP, help="FPL bootstrap JSON"
    )
    common.add_argument(
        "--dry-run", action="store_true", help="只预览，不写文件"
    )
    # 子命令用的全局选项：default=SUPPRESS 使其不会覆盖主解析器已解析出的值
    # （否则子解析器会把 --swift 重置成默认真实路径，导致误写真实源文件）
    sub_common = argparse.ArgumentParser(add_help=False)
    sub_common.add_argument("--swift", default=argparse.SUPPRESS, help="PlayerNames.swift 路径")
    sub_common.add_argument(
        "--bootstrap", default=argparse.SUPPRESS, help="FPL bootstrap JSON"
    )
    sub_common.add_argument(
        "--dry-run", action="store_true", default=argparse.SUPPRESS, help="只预览，不写文件"
    )
    p = argparse.ArgumentParser(
        parents=[common], description="EPL Viewer 球员中英文名维护工具"
    )
    sub = p.add_subparsers(dest="cmd")

    sub.add_parser("stats", parents=[sub_common], help="覆盖率统计")
    pl = sub.add_parser("list", parents=[sub_common], help="列出球员")
    pl.add_argument("--missing", action="store_true")
    pl.add_argument("--team", default=None)
    pl.add_argument("--search", default=None)
    ps = sub.add_parser("show", parents=[sub_common], help="看一名球员")
    ps.add_argument("id", type=int)
    pi = sub.add_parser("set-id", parents=[sub_common], help="按 id 改/加")
    pi.add_argument("id", type=int)
    pi.add_argument("name")
    pn = sub.add_parser("set-name", parents=[sub_common], help="按 web_name 改/加")
    pn.add_argument("web_name")
    pn.add_argument("name")
    pn.add_argument("--force", action="store_true")
    sub.add_parser("interactive", parents=[sub_common], help="交互模式")
    return p


def main():
    args = build_parser().parse_args()
    if args.cmd is None:
        build_parser().print_help()
        return
    if args.cmd == "stats":
        cmd_stats(args)
    elif args.cmd == "list":
        cmd_list(args)
    elif args.cmd == "show":
        cmd_show(args)
    elif args.cmd == "set-id":
        cmd_set_id(args)
    elif args.cmd == "set-name":
        cmd_set_name(args)
    elif args.cmd == "interactive":
        cmd_interactive(args)


if __name__ == "__main__":
    main()
