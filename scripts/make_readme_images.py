#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Unit Frames (docs/images/ui_*.png, settings_*.png).

The frames are rebuilt from the sizes, colours and strings in the addon code
(Modules/UnitButton.lua SIZES, Modules/Frames.lua layout, Core/Init.lua Style and
DEFAULTS, Core/Locales.lua, UI/OptionsWindow.lua), in game pixels x SCALE.
Portraits and spell icons are simplified shapes; every name is made up.

usage: python scripts/make_readme_images.py .
Renders with a local headless Chrome (set CHROME=<path> if it is not found).
"""
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CALL = "#f2b45a"
PAGE_W = 1600

# ---------------------------------------------------------------------------
# Values read from the Lua code
# ---------------------------------------------------------------------------


def read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


def parse_sizes(src):
    out = {}
    block = re.search(r"ns\.SIZES\s*=\s*\{(.*?)\n\}", src, re.S).group(1)
    for key, body in re.findall(r"(\w+)\s*=\s*\{([^}]*)\}", block):
        d = {}
        for k, v in re.findall(r"(\w+)\s*=\s*(\w+)", body):
            d[k] = True if v == "true" else (False if v == "false" else int(v))
        out[key] = d
    return out


def parse_style(src):
    block = re.search(r"ns\.Style\s*=\s*\{(.*?)\n\}", src, re.S).group(1)
    out = {}
    for k, body in re.findall(r"(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", block):
        out[k] = [float(v) for v in body.split(",") if v.strip()]
    return out


def parse_defaults(src):
    block = re.search(r"ns\.DEFAULTS\s*=\s*\{(.*?)\n\}", src, re.S).group(1)
    return {k: v == "true" for k, v in re.findall(r"^\s*(\w+)\s*=\s*(true|false)", block, re.M)}


def parse_locale(src, lang):
    start = src.index(f"    {lang} = {{")
    end = src.index("\n    },", start)
    return {k: v for k, v in re.findall(r'(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', src[start:end])}


def parse_version(src):
    m = re.search(r"^## Version:\s*(\S+)", src, re.M)
    return m.group(1) if m else ""


def css(c, alpha=None, mul=1.0):
    r, g, b = (round(v * mul * 255) for v in c[:3])
    a = alpha if alpha is not None else (c[3] if len(c) > 3 else 1)
    return f"rgba({r},{g},{b},{a:.2f})"


# Frame centres in the picture. Same arrangement as DEFAULT_POS in Modules/Frames.lua
# (party and focus on the left, pet left of the player, target right, target of target
# right of the target) with tighter spacing so the frames stay readable.
SCENE_POS = {
    "player": (-160, -170), "target": (190, -170), "targettarget": (420, -150),
    "focus": (-190, 40), "pet": (-420, -175), "party": (-470, 95),
}

# PowerBarColor / FACTION_BAR_COLORS / class colours of the client
MANA = (0.0, 0.0, 1.0)
ENERGY = (1.0, 1.0, 0.0)
HOSTILE = (0.8, 0.3, 0.22)
NEUTRAL = (0.9, 0.7, 0.0)
CLASS = {"DRUID": (1.0, 0.49, 0.04), "PALADIN": (0.96, 0.55, 0.73), "MAGE": (0.25, 0.78, 0.92),
         "PRIEST": (1.0, 1.0, 1.0), "ROGUE": (1.0, 0.96, 0.41)}
DIFF_YELLOW = (1.0, 1.0, 0.0)          # same level
DIFF_GREEN = (0.25, 0.75, 0.25)        # a few levels below
PLAYER_LEVEL = (1.0, 0.82, 0.0)
DISPEL = {"Magic": (0.2, 0.6, 1.0), "Poison": (0.0, 0.6, 0.0)}
DEFAULT_DEBUFF = (0.8, 0.1, 0.1)
BUFF_BORDER = (0.2, 0.25, 0.3)
THREAT_2 = (1.0, 0.6, 0.0)             # ns.Style.threat[2]
PLATE_THREAT_2 = (1.0, 0.5, 0.1)       # Nameplates THREAT_DPS[2]
HEAL_MINE = (0.35, 1.0, 0.45, 0.55)    # UnitButton.lua heal prediction
HEAL_OTHER = (0.35, 0.85, 1.0, 0.40)
LOSS_COLOR = (0.85, 0.15, 0.15, 0.9)   # HealthEffects.lua hit trail
# Auras.lua
TARGET_COLUMNS, AURA_GAP, BIG_FACTOR = 8, 3, 1.4
PARTY_SIZE, PARTY_GAP = 20, 2
PARTY_BUFF_SIZE, PARTY_BUFF_BIG, PARTY_BIG_LINES = 16, 18, 2
PARTY_FRAME_GAP = 10                   # Frames.lua PARTY_GAP

# ---------------------------------------------------------------------------
# Texts (scene names are made up; UI strings come from Core/Locales.lua)
# ---------------------------------------------------------------------------
T = {
    "ko": {
        "lead": "내 캐릭터·대상·대상의 대상·주시 대상·소환수·파티 프레임과 적·아군 이름표를 EzWoW 스타일로",
        "me": "이끼발톱", "target": "덤불숲 강도", "focus": "덤불숲 주술사", "boar": "가시등 멧돼지",
        "party": ["은빛방패", "잿빛서리", "들꽃노래", "검은송곳"],
        "castTarget": "어둠의 화살", "castFocus": "치유의 물결",
        "notes": [
            ("내 캐릭터", "초상화, 이름 줄과 호박색 선, 직업 색 체력바(현재 · %), 위협 수준 테두리."),
            ("기력 틱·마나 5초 규칙", "기력 바 위의 불꽃이 2초 기력 틱을 따라갑니다. 마나 직업은 마나를 쓰면 금색 불꽃이 5초를 센 뒤 2초 마나 틱을 보여 줍니다."),
            ("연계 점수·드루이드 마나", "도적·드루이드 연계 점수 5칸, 변신 중에는 그 아래 마나 바."),
            ("내 버프·디버프", "디버프 먼저, 버프는 다음 줄. 내가 건 것은 금색 테두리."),
            ("대상", "적대 대상은 산호색 선. 레벨(난이도 색)·정예 표시, 공격대 징표."),
            ("시전바", "호박색 시전, 하늘색 정신 집중. 차단할 수 없는 주문은 회색 + 방패, 차단되면 \"차단됨\"."),
            ("대상 버프·디버프", "내가 건 효과는 1.4배 크기로 첫 줄(금색 테두리), 다른 디버프(해제 종류 색 테두리)와 버프는 다음 줄. 내 디버프만 보기 옵션."),
            ("대상의 대상", "대상이 노리는 상대의 작은 체력바."),
            ("주시 대상", "대상처럼 시전바는 위, 버프·디버프는 아래(내가 건 것은 크게). 그림은 차단할 수 없는 시전(회색 + 방패)."),
            ("소환수", "소환수가 있을 때 나타납니다. 그림은 잠금 해제(이동) 중의 미리보기 모양."),
            ("파티", "파티장 아이콘, 오른쪽에 디버프 4개, 아래에 버프 줄(내가 건 버프는 크게), 내가 해제할 수 있는 디버프는 체력바 테두리 색, 사거리 밖 파티원은 흐리게. 가로 배열 옵션."),
            ("퀘스트 몹 표시", "퀘스트 목표인 적의 이름표 위에 \"!\" 표시."),
            ("대상 이름표", "테두리 강조, 위협 색(딜러·탱커 기준), 내가 건 디버프, 시전바, 공격대 징표. 대상이 아닌 이름표는 흐리게. 차단할 수 있는 시전은 깜박이는 테두리와 \"차단!\"(내 차단 기술이 재사용 대기 중이면 보라색)."),
            ("체력바 효과", "광택과 가장자리 불꽃, 전투 중 맥동, 낮은 체력 경고. 맞으면 빨간 잔상과 번쩍임, 회복되면 초록 잔상."),
            ("예상 치유량", "들어오는 치유가 체력바 뒤로 이어집니다. 내 치유는 초록, 다른 사람의 치유는 하늘색."),
            ("아군 이름표", "기본은 이름만: 플레이어는 직업 색, NPC는 관계 색, 파티원은 조금 크게. 이름 + 얇은 체력바, 기본 모양도 고를 수 있습니다. 던전 안에서는 게임 설정(이름만·숨기기)만 씁니다."),
        ],
        "sLead": "/ezuf · 사용할 프레임, 표시, 이름표, 체력 글자, 크기·위치",
        "sTitle": "설정창",
        "sNotes": [
            ("사용할 프레임", "내 캐릭터 · 대상 · 대상의 대상 · 주시 대상 · 소환수 · 파티를 각각 켜고 끕니다."),
            ("표시", "직업 색, 초상화, 시전바, 버프·디버프, 연계 점수, 드루이드 마나, 파티 버프·디버프·사거리, 위협 테두리, 기본 프레임 숨기기, 기력 틱·마나 5초 규칙, 체력바·피격·회복 효과, 예상 치유량, 내가 건 효과 크게, 파티창 가로 배열."),
            ("이름표", "EzWoW 이름표, 시전바, 내 디버프, 위협 색(탱커 기준), 대상 아닌 이름표 흐리게, 퀘스트 몹 표시, 차단 경고(이름표·대상·주시 시전바, 대상·주시만, 소리), 아군 이름표(기본 모양 · 이름만 · 이름 + 얇은 체력바, 던전 안에서 숨기기), 이름표 크기 70~160%."),
            ("체력 글자", "큰 프레임 · 작은 프레임 · 파티 각각: 현재 · %, 현재 / 최대, 현재, %, 부족량, 표시 안 함."),
            ("크기·위치", "프레임 크기 60~160%, 잠금 해제 후 끌어서 이동(전투 시작 시 자동 잠금), 위치 초기화, 언어. 잠긴 상태에서도 Ctrl + 끌기로 이동, Ctrl + 휠로 프레임마다 크기 50~200%(전투 중 제외)."),
        ],
        "sFoot": "애드온 코드의 창 크기·좌표·색상·문구로 재현한 예시 화면입니다. 체크 상태는 기본값입니다.",
        "foot": "애드온 코드의 프레임 크기·색상·문구로 재현한 예시 화면입니다. 배치는 기본 위치와 같은 순서로 두고 간격만 좁혔습니다. 초상화·아이콘 그림은 단순화했고, 이름은 지어낸 예시입니다.",
    },
    "en": {
        "lead": "Player, target, target of target, focus, pet and party frames plus enemy and friendly nameplates, in EzWoW style",
        "me": "Mossclaw", "target": "Thicket Bandit", "focus": "Thicket Shaman", "boar": "Thornback Boar",
        "party": ["Silvershield", "Ashfrost", "Wildsong", "Darkfang"],
        "castTarget": "Shadow Bolt", "castFocus": "Healing Wave",
        "notes": [
            ("Player", "Portrait, name strip with the amber line, class-coloured health (current · %), threat border."),
            ("Energy ticks · mana 5-second rule", "A spark on the energy bar follows the 2-second energy tick. For mana users a gold spark counts the 5 seconds after you spend mana, then shows the 2-second mana ticks."),
            ("Combo points · druid mana", "Five combo point pips for rogues and druids, and a mana bar below them while shapeshifted."),
            ("Your buffs & debuffs", "Debuffs first, buffs on the next row. Yours have a gold border."),
            ("Target", "Coral line for hostile units. Level (difficulty colour), elite tag, raid marker."),
            ("Cast bar", "Amber casts, light blue channels. Uninterruptible spells are grey with a shield; \"Interrupted\" on kicks."),
            ("Target buffs & debuffs", "Yours first at 1.4x size (gold border), then other debuffs (bordered by dispel type) and buffs on the next rows. Option to show only your debuffs."),
            ("Target of target", "A small health bar of whoever your target is attacking."),
            ("Focus", "Like the target: cast bar above, buffs and debuffs below (yours larger). Shown with an uninterruptible cast (grey + shield)."),
            ("Pet", "Shown when you have a pet. Pictured in its unlocked (move) preview look."),
            ("Party", "Leader icon, 4 debuffs on the right, a buff row below (yours larger), a coloured health border for debuffs you can dispel, faded out-of-range members. Side-by-side option."),
            ("Quest mob marker", "A \"!\" above the nameplates of enemies you need for a quest."),
            ("Target nameplate", "Outlined, threat colours (DPS or tank view), your debuffs, cast bar, raid marker. Other plates fade. Interruptible casts get a pulsing rim and \"Kick!\" (purple while your interrupt is on cooldown)."),
            ("Health bar effects", "Gloss and an edge spark, a combat pulse, a low-health warning. A red trail and flash when hit, a green trail when healed."),
            ("Incoming heals", "Heals on the way continue the health fill: yours in green, others' in light blue."),
            ("Friendly nameplates", "Name only by default: class colour for players, reaction colour for NPCs, party members a little larger. Or name + thin health bar, or the default look. Inside instances only the game's own settings are used (names only, hide)."),
        ],
        "sLead": "/ezuf · frames, display, nameplates, health text, size & position",
        "sTitle": "Settings",
        "sNotes": [
            ("Frames", "Turn player, target, target of target, focus, pet and party on or off one by one."),
            ("Display", "Class colours, portraits, cast bars, buffs and debuffs, combo points, druid mana, party buffs, debuffs and range, threat border, hide default frames, energy ticks and mana 5-second rule, health bar, hit and heal effects, incoming heals, larger auras you cast, party side by side."),
            ("Nameplates", "EzWoW plates, cast bars, your debuffs, threat colours (tank view), fade non-target plates, quest mob marker, interrupt warning (plate, target and focus cast bars; target & focus only; sound), friendly plates (default, name only, name + thin bar; hide in instances), plate size 70–160%."),
            ("Health text", "For big frames, small frames and party: current · %, current / max, current, %, deficit, hidden."),
            ("Size & position", "Frame size 60–160%, unlock to drag (locks again in combat), reset positions, language. Even when locked, Ctrl + drag moves a frame and Ctrl + mouse wheel sizes it 50–200% (not in combat)."),
        ],
        "sFoot": "Mock-up rebuilt from the window size, coordinates, colours and strings in the addon code. Check boxes show the defaults.",
        "foot": "Mock-ups rebuilt from the frame sizes, colours and strings in the addon code. Frames keep the default arrangement with tighter spacing. Portraits and icons are simplified; all names are made up.",
    },
}

# ---------------------------------------------------------------------------
# Page parts
# ---------------------------------------------------------------------------
S = 1.1  # current scale (game px -> page px); set per page


def px(v):
    return f"{v * S:.2f}px"


OUTLINE = "text-shadow:-1px 0 #000,1px 0 #000,0 -1px #000,0 1px #000,0 0 2px #000;"

CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { width: 1600px; overflow: hidden; background: #0f1a14; font-family: 'Noto Sans KR','Malgun Gothic',sans-serif; color: #edf4f7; }
.page { position: relative; padding: 34px 50px 40px; }
h1 { color: #f2b45a; font-size: 40px; font-weight: 700; letter-spacing: .3px; display: flex; align-items: center; gap: 14px; }
h1 .badge { font-size: 15px; background: #f2b45a; color: #1a1206; padding: 2px 9px; border-radius: 5px; }
.lead { color: #d5dde2; font-size: 19px; margin-top: 6px; }
.abs { position: absolute; }
.ground { position: absolute; border-radius: 10px; background: radial-gradient(ellipse at 50% 40%, #2c4630 0%, #213827 55%, #1a2d20 100%);
  box-shadow: inset 0 0 60px rgba(0,0,0,.35); }
.t { position: absolute; white-space: nowrap; line-height: 1; }
.call { position: absolute; width: 30px; height: 30px; border-radius: 50%; background: #f2b45a; color: #1d1405; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #1a1206; box-shadow: 0 0 0 2px #f2b45a55; z-index: 50; }
.notes { position: absolute; }
.note { display: flex; gap: 12px; margin-bottom: 10px; font-size: 16px; line-height: 1.5; color: #dfe6ea; }
.note .n { flex: none; width: 28px; height: 28px; border-radius: 50%; background: #f2b45a; color: #1d1405; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; margin-top: 0px; }
.note b { color: #fff; }
.foot { color: #8a9a92; font-size: 13.5px; }
.fit { display: inline-block; }
"""

FIT_JS = """
<script>
document.querySelectorAll('[data-fit]').forEach(function (e) {
  var max = parseFloat(e.dataset.fit), min = parseFloat(e.dataset.min || 8);
  var fs = parseFloat(getComputedStyle(e).fontSize);
  while (e.scrollWidth > max && fs > min) { fs -= 0.25; e.style.fontSize = fs + 'px'; }
  if (e.scrollWidth > max) { e.style.maxWidth = max + 'px'; e.style.overflow = 'hidden'; e.style.textOverflow = 'ellipsis'; }
});
</script>
"""


def box(x, y, w, h, style="", inner=""):
    return f'<div class="abs" style="left:{px(x)};top:{px(y)};width:{px(w)};height:{px(h)};{style}">{inner}</div>'


def text(x, y, s, size, color="#fff", style="", anchor="left", h=None):
    """Font string. y = vertical centre (game px); anchor left/right/center at x."""
    tr = {"left": "translate(0,-50%)", "right": "translate(-100%,-50%)", "center": "translate(-50%,-50%)"}[anchor]
    return (f'<div class="t" style="left:{px(x)};top:{px(y)};font-size:{px(size)};color:{color};'
            f'transform:{tr};{OUTLINE}{style}">{s}</div>')


def bar(x, y, w, h, frac, color, bg=None, shine=True, extra="", after=()):
    """after: (fraction, rgba) segments continuing the fill (heal prediction, hit trail)."""
    bgc = bg or css(color, 0.9, 0.22)
    fill = f'<div class="abs" style="left:0;top:0;bottom:0;width:{frac * 100:.1f}%;background:{css(color, 1)}">'
    if shine:
        fill += '<div class="abs" style="inset:0;background:linear-gradient(to bottom,rgba(255,255,255,.16),rgba(255,255,255,0))"></div>'
    fill += "</div>"
    at = frac
    for seg, col in after:
        seg = min(seg, 1 - at)
        fill += (f'<div class="abs" style="left:{at * 100:.1f}%;top:0;bottom:0;width:{seg * 100:.1f}%;'
                 f'background:{css(col[:3], col[3])}"></div>')
        at += seg
    return box(x, y, w, h, f"background:{bgc};overflow:visible", fill + extra)


# simplified art --------------------------------------------------------------
ICONS = {
    "moon": ("#1b2a4a", '<circle cx="50" cy="50" r="30" fill="#cfe3ff"/><circle cx="62" cy="42" r="26" fill="#1b2a4a"/>'),
    "claw": ("#3a1414", '<path d="M25 80 L45 20 M45 82 L62 22 M65 84 L80 28" stroke="#ff6a5a" stroke-width="9" stroke-linecap="round"/>'),
    "fairy": ("#2a1840", '<path d="M50 14 L58 42 L86 50 L58 58 L50 86 L42 58 L14 50 L42 42 Z" fill="#d79cff"/>'),
    "wild": ("#203a1c", '<circle cx="50" cy="60" r="16" fill="#9be07a"/><circle cx="30" cy="36" r="9" fill="#9be07a"/><circle cx="50" cy="28" r="9" fill="#9be07a"/><circle cx="70" cy="36" r="9" fill="#9be07a"/>'),
    "thorns": ("#26331a", '<path d="M50 12 L60 40 L88 30 L66 52 L84 78 L54 66 L44 90 L38 62 L12 70 L32 48 L14 26 L42 36 Z" fill="#a6c35a"/>'),
    "cat": ("#3a2a1a", '<path d="M24 82 L24 34 L36 18 L44 34 L56 34 L64 18 L76 34 L76 82 Z" fill="#c9965a"/><circle cx="40" cy="50" r="5" fill="#2a1a0a"/><circle cx="60" cy="50" r="5" fill="#2a1a0a"/>'),
    "poison": ("#16301a", '<path d="M50 14 C64 38 74 52 74 64 A24 24 0 0 1 26 64 C26 52 36 38 50 14 Z" fill="#5fd05a"/>'),
    "frost": ("#14283a", '<path d="M50 12 V88 M17 31 L83 69 M17 69 L83 31" stroke="#bfe6ff" stroke-width="9" stroke-linecap="round"/>'),
    "shadow": ("#1e1430", '<circle cx="50" cy="50" r="28" fill="#8a5ad8"/><circle cx="50" cy="50" r="14" fill="#2a1840"/>'),
    "wave": ("#10304a", '<path d="M10 60 C25 35 40 35 50 55 C60 75 75 75 90 50" stroke="#7fd0ff" stroke-width="12" fill="none" stroke-linecap="round"/>'),
    "fort": ("#1c2a44", '<path d="M50 12 L60 40 L88 50 L60 60 L50 88 L40 60 L12 50 L40 40 Z" fill="#f2f6ff"/><circle cx="50" cy="50" r="10" fill="#9fc4ff"/>'),
    "arcane": ("#241a44", '<circle cx="50" cy="50" r="30" fill="none" stroke="#b9a2ff" stroke-width="8"/><circle cx="50" cy="50" r="12" fill="#e2d8ff"/>'),
    "sunder": ("#2e2e2e", '<path d="M50 14 L80 26 C80 58 68 74 50 86 C32 74 20 58 20 26 Z" fill="#9a9a9a"/><path d="M50 20 L44 50 L56 52 L48 84" stroke="#2e2e2e" stroke-width="6" fill="none"/>'),
}


def icon_svg(kind):
    bg, shape = ICONS[kind]
    return (f'<svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none" style="display:block">'
            f'<rect width="100" height="100" fill="{bg}"/>{shape}<rect width="100" height="100" fill="url(#shade)"/></svg>')


def portrait_svg(kind):
    if kind == "druid":
        body = ('<rect width="100" height="100" fill="#2a3a24"/><ellipse cx="50" cy="104" rx="40" ry="30" fill="#4e6b3a"/>'
                '<circle cx="50" cy="52" r="24" fill="#8a6a4a"/><path d="M26 44 C30 18 70 18 74 44 C66 34 34 34 26 44 Z" fill="#3e5a2a"/>'
                '<path d="M22 36 L12 14 L30 30 M78 36 L88 14 L70 30" stroke="#c9b48a" stroke-width="5" fill="none"/>'
                '<circle cx="42" cy="54" r="3.5" fill="#e8ffd0"/><circle cx="58" cy="54" r="3.5" fill="#e8ffd0"/>')
    else:  # bandit
        body = ('<rect width="100" height="100" fill="#3a2420"/><ellipse cx="50" cy="104" rx="40" ry="30" fill="#5a3a2a"/>'
                '<circle cx="50" cy="54" r="24" fill="#c8946c"/><path d="M24 48 C26 22 74 22 76 48 Z" fill="#9b2a22"/>'
                '<rect x="28" y="56" width="44" height="18" fill="#3a2a22"/><circle cx="42" cy="50" r="3" fill="#1a0a0a"/><circle cx="58" cy="50" r="3" fill="#1a0a0a"/>')
    return (f'<svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none" style="display:block">{body}'
            '<rect width="100" height="100" fill="url(#shade)"/></svg>')


def skull(size):
    return (f'<svg width="{px(size)}" height="{px(size)}" viewBox="0 0 100 100" style="display:block">'
            '<path d="M50 8 C24 8 12 26 12 46 C12 60 20 68 28 72 V90 H72 V72 C80 68 88 60 88 46 C88 26 76 8 50 8 Z" fill="#f4f4f4" stroke="#222" stroke-width="5"/>'
            '<circle cx="35" cy="46" r="11" fill="#222"/><circle cx="65" cy="46" r="11" fill="#222"/>'
            '<path d="M40 76 V88 M50 76 V88 M60 76 V88" stroke="#222" stroke-width="4"/></svg>')


def crown(size):
    return (f'<svg width="{px(size)}" height="{px(size)}" viewBox="0 0 100 100" style="display:block">'
            '<path d="M10 80 L16 30 L36 52 L50 18 L64 52 L84 30 L90 80 Z" fill="#ffd34a" stroke="#4a3200" stroke-width="7"/></svg>')


def shield(size):
    return (f'<svg width="{px(size)}" height="{px(size)}" viewBox="0 0 100 100" style="display:block">'
            '<path d="M50 6 L88 20 C88 56 74 80 50 94 C26 80 12 56 12 20 Z" fill="#b8bcc4" stroke="#3a3d44" stroke-width="7"/></svg>')


def aura(x, y, size, kind, border, count=None, alpha=1.0, swipe=None):
    inner = f'<div class="abs" style="inset:0">{icon_svg(kind)}</div>'
    if swipe:
        inner += (f'<div class="abs" style="inset:0;'
                  f'background:conic-gradient(rgba(0,0,0,.55) 0 {swipe}%, transparent {swipe}% 100%)"></div>')
    if count:
        inner += text(size + 1, size - 6, count, 10, "#fff", anchor="right")
    return box(x, y, size, size, f"border:{px(1)} solid {css(border, 1)};opacity:{alpha}", inner)


# ---------------------------------------------------------------------------
# Unit frame (Modules/UnitButton.lua LayoutUnitButton)
# ---------------------------------------------------------------------------
def frame_height(size):
    info = size.get("info", 0) + 2 if size.get("info", 0) > 0 else 0
    return 2 + info + size["health"] + (size["power"] + 1 if size["power"] > 0 else 0)


def unit_frame(st, sizes, key, d):
    """Returns (html, w, h) of a unit button at (0,0)."""
    size = sizes[key]
    H = frame_height(size)
    pw = H if size.get("portrait") else 0
    W = size["w"] + pw
    side = d.get("portraitSide", "LEFT")
    left = pw if (pw and side == "LEFT") else 1
    right = pw if (pw and side == "RIGHT") else 1
    inner_w = W - left - right
    big_font = 10 if key in ("small", "pet") else 12
    name_font = 10 if size.get("info", 0) > 0 else big_font
    p = []
    border = css(d.get("threat") or st["border"], 1)
    if pw:
        px0 = 1 if side == "LEFT" else W - pw + 1
        p.append(box(px0, 1, pw - 2, H - 2, "background:rgba(0,0,0,.6);overflow:hidden", portrait_svg(d["portrait"])))
    top = 1
    info = size.get("info", 0)
    if info:
        p.append(box(left, 1, inner_w, info, f"background:{css(st['bgSecondary'], .95)}"))
        p.append(box(left, 1 + info, inner_w, 2, f"background:{css(d['accent'], 1)}"))
        top = 1 + info + 2
    hy = top
    p.append(bar(left, hy, inner_w, size["health"], d["hp"], d["hpColor"], after=d.get("after", ())))
    if d.get("dispelGlow"):
        p.append(box(left - 1, hy - 1, inner_w + 2, size["health"] + 2, f"border:{px(2)} solid {css(d['dispelGlow'], 1)};z-index:3"))
    if size["power"] > 0:
        spark = ""
        if d.get("spark") is not None:
            sw, sh = 12, size["power"] * 2.2
            sx = inner_w * d["spark"] - sw / 2
            spark = (f'<div class="abs" style="left:{px(sx)};top:{px((size["power"] - sh) / 2)};width:{px(sw)};height:{px(sh)};'
                     'background:radial-gradient(ellipse at center,rgba(255,255,255,1) 0%,rgba(255,255,240,.85) 22%,rgba(255,255,220,0) 70%);'
                     'mix-blend-mode:screen;z-index:4"></div>')
        p.append(bar(left, hy + size["health"] + 1, inner_w, size["power"], d["pp"], d["ppColor"], extra=spark))
    # texts
    cy_info = 1 + info / 2 if info else hy + size["health"] / 2
    cy_hp = hy + size["health"] / 2
    name_x = left + 4
    if size.get("level"):
        p.append(text(left + 4, cy_info, d["level"], name_font, css(d["levelColor"], 1)))
        lvl_w = len(d["level"]) * name_font * 0.58 + 3
        name_x = left + 4 + lvl_w
    name_max = (left + inner_w - 4 - name_x) if info else (inner_w - 4 - 4 - 34)
    p.append(f'<div class="t" style="left:{px(name_x)};top:{px(cy_info)};font-size:{px(name_font)};color:#fff;transform:translate(0,-50%);'
             f'{OUTLINE}max-width:{px(name_max)};overflow:hidden">{d["name"]}</div>')
    p.append(text(left + inner_w - 4, cy_hp, d["hpText"], big_font, "#fff", anchor="right"))
    if size.get("powerText") and size["power"] >= 10 and d.get("ppText"):
        p.append(text(left + inner_w - 3, hy + size["health"] + 1 + size["power"] / 2, d["ppText"], 10, "#fff", anchor="right"))
    if d.get("leader"):
        p.append(f'<div class="abs" style="left:{px(8 - 6)};top:{px(-6)};z-index:5">{crown(12)}</div>')
    if d.get("raid"):
        p.append(f'<div class="abs" style="left:{px(W / 2 - 8)};top:{px(-1 - 8)};z-index:5">{skull(16)}</div>')
    if d.get("combat"):
        p.append(f'<div class="t" style="left:{px(2)};top:{px(H - 2)};transform:translate(-50%,-50%);font-size:{px(14)};color:#ff4a3a;{OUTLINE}z-index:5">⚔</div>')
    body = "".join(p)
    style = (f"background:{css(st['frameBg'])};box-shadow:inset 0 0 0 {px(1)} {border};opacity:{d.get('alpha', 1)}")
    return body, W, H, style


def castbar(x, y, w, h, frac, color, label, time, st, locked=False, small=False, icon="shadow", kick=None):
    """Castbar status bar at (x,y) game px; icon frame h x h to its left (-2).
    kick = warning label: the interrupt warning rim (2 px + a 2 px halo, Castbar.lua) and label."""
    p = []
    if kick:
        k = st["kickReady"]
        p.append(box(x - 4, y - 4, w + 8, h + 8, f"border:{px(2)} solid {css(k, .35)}"))
        p.append(box(x - 2, y - 2, w + 4, h + 4, f"border:{px(2)} solid {css(k, 1)}"))
        p.append(text(x + w + 7, y + h / 2, kick, 9 if h < 14 else 11, css(k, 1)))
    p.append(box(x - 2 - h, y, h, h, f"border:{px(1)} solid {css(st['border'])};background:#000",
                 f'<div class="abs" style="inset:0">{icon_svg(icon)}</div>'))
    fill = f'<div class="abs" style="left:0;top:0;bottom:0;width:{frac * 100:.1f}%;background:{css(color, 1)}"></div>'
    fs = 8 if small else 10
    fill += text(4, h / 2 - 1, label, fs, "#fff")
    if not small:
        fill += text(w - 4 - 2, h / 2 - 1, time, fs, "#fff", anchor="right")
    p.append(box(x, y, w, h, f"background:{css(st['frameBg'])};border:{px(1)} solid {css(st['border'])}", fill))
    if locked:
        p.append(f'<div class="abs" style="left:{px(x - 2 - h + h / 2 - h)};top:{px(y + h / 2 - h + 1)};width:{px(2 * h)};height:{px(2 * h)};'
                 f'display:flex;align-items:center;justify-content:center;z-index:6">{shield(h * 1.25)}</div>')
    return "".join(p)


# ---------------------------------------------------------------------------
# UI scene
# ---------------------------------------------------------------------------
def notes_height(notes, width):
    """Rough height of a notes column (16px text, 24px lines, 10px gaps)."""
    import math
    total = 0
    for a, b in notes:
        w = sum(15.5 if ord(ch) > 0x2E80 else 8.3 for ch in a + " — " + b)
        total += math.ceil(w / width) * 24 + 10
    return total


def ui_page(lang, ctx):
    global S
    S = 1.4
    t, L, st, sizes = T[lang], ctx["L"][lang], ctx["style"], ctx["sizes"]
    pos = SCENE_POS
    TOP, BOTTOM = 285, -335           # game y range of the scene
    LEFT, RIGHT = -540, 535
    gx0, gy0 = 48, 168                 # page px of the ground's top-left
    ox = gx0 + (-LEFT) * S             # page px of the screen centre
    oy = gy0 + TOP * S

    def X(x):
        return ox + x * S

    def Y(y):
        return oy - y * S

    parts = [f'<div class="ground" style="left:{gx0}px;top:{gy0}px;width:{(RIGHT - LEFT) * S:.0f}px;height:{(TOP - BOTTOM) * S:.0f}px"></div>']
    rects = {}

    def place(key, cx, cy, d):
        body, W, H, style = unit_frame(st, sizes, key, d)
        x0, y0 = X(cx) - W * S / 2, Y(cy) - H * S / 2
        parts.append(f'<div class="abs" style="left:{x0:.1f}px;top:{y0:.1f}px;width:{px(W)};height:{px(H)};{style}">{body}')
        rects[d["id"]] = (x0, y0, W, H)
        return W, H

    def close():
        parts.append("</div>")

    accent, warning = st["accent"], st["warning"]
    # player: druid in cat form (energy), combo points on the target, druid mana
    pW, pH = place("big", *pos["player"], dict(id="player", portrait="druid", portraitSide="LEFT", accent=accent,
                   level="12", levelColor=PLAYER_LEVEL, name=t["me"], hp=0.81, hpColor=CLASS["DRUID"], hpText="486 · 81%",
                   pp=0.64, ppColor=ENERGY, ppText="64", spark=0.42, threat=THREAT_2, combat=True))
    # extras (Frames.lua buildPlayerExtras): health bottom -16, 5 pips h6 gap 3, mana h5 at -9
    size = sizes["big"]
    hb = 1 + size["info"] + 2 + size["health"]
    hw = pW - pH - 1
    pip_w = (hw - 4 * 3) / 5
    for i in range(1, 6):
        col = css((1, 0.82 - i * 0.08, 0.2), 1) if i <= 3 else css((0.15, 0.17, 0.2), .9)
        parts.append(box(pH + (i - 1) * (pip_w + 3), hb + 16, pip_w, 6, f"background:{col}"))
    parts.append(box(pH, hb + 16 + 9, hw, 5, f"background:{css(st['frameBg'])};border:{px(1)} solid {css(st['border'])}",
                     f'<div class="abs" style="left:0;top:0;bottom:0;width:70%;background:{css((0.31, 0.45, 0.85))}"></div>'))
    # player auras: 26 below the frame, 8 columns
    asz = (pW - 7 * 3) // 8
    for i, (kind, border, cnt, sw) in enumerate([("wild", BUFF_BORDER, None, None), ("thorns", BUFF_BORDER, None, 30), ("cat", BUFF_BORDER, None, None)]):
        parts.append(aura(i * (asz + 3), pH + 26, asz, kind, border, cnt, swipe=sw))
    close()

    # target with cast bar (above) and auras (below)
    tW, tH = place("big", *pos["target"], dict(id="target", portrait="bandit", portraitSide="RIGHT", accent=warning,
                   level="13", levelColor=DIFF_YELLOW, name=t["target"], hp=0.64, hpColor=HOSTILE, hpText="312 · 64%",
                   pp=0.48, ppColor=MANA, ppText="208", raid=True, threat=THREAT_2, after=[(0.08, LOSS_COLOR)]))
    parts.append(castbar(16 + 2, -4 - 16, tW - 18, 16, 0.62, st["castbar"], t["castTarget"], "1.1", st))
    # Auras.lua "big" shape: my debuffs (x1.4), other debuffs, my buffs (x1.4), other buffs; each kind on a new row
    asz = (tW - (TARGET_COLUMNS - 1) * AURA_GAP) // TARGET_COLUMNS
    big = round(asz * BIG_FACTOR)
    y = tH + 4
    for i, (kind, sw) in enumerate([("moon", 40), ("claw", 65)]):
        parts.append(aura(i * (big + AURA_GAP), y, big, kind, accent, None, 1, sw))
    y += big + AURA_GAP
    for i, (kind, border, cnt) in enumerate([("fairy", DISPEL["Magic"], None), ("sunder", DEFAULT_DEBUFF, "3")]):
        parts.append(aura(i * (asz + AURA_GAP), y, asz, kind, border, cnt, .85))
    y += asz + AURA_GAP
    parts.append(aura(0, y, asz, "shadow", BUFF_BORDER))
    close()

    # target of target (me)
    place("small", *pos["targettarget"], dict(id="tot", accent=accent, name=t["me"], hp=0.81, hpColor=CLASS["DRUID"], hpText="81%"))
    close()

    # focus: enemy shaman with an uninterruptible cast (below the frame)
    fW, fH = place("focus", *pos["focus"], dict(id="focus", accent=warning, level="14+", levelColor=DIFF_YELLOW, name=t["focus"],
                   hp=0.92, hpColor=HOSTILE, hpText="398 · 92%", pp=0.7, ppColor=MANA))
    parts.append(castbar(16 + 2, -4 - 16, fW - 18, 16, 0.35, st["castLocked"], t["castFocus"], "1.9", st, locked=True, icon="wave"))
    fsz = (fW - (TARGET_COLUMNS - 1) * AURA_GAP) // TARGET_COLUMNS
    fbig = round(fsz * BIG_FACTOR)
    parts.append(aura(0, fH + 4, fbig, "moon", accent, None, 1, 25))
    parts.append(aura(0, fH + 4 + fbig + AURA_GAP, fsz, "wave", BUFF_BORDER))
    close()

    # pet: preview look (edit mode)
    place("pet", *pos["pet"], dict(id="pet", accent=accent, name=L["pet"], hp=0.72, hpColor=accent, hpText="72%",
                                   pp=0.55, ppColor=(0.31, 0.45, 0.85), alpha=1))
    close()

    # party (holder top-left at centre - size/2)
    psz = sizes["party"]
    ph = frame_height(psz)
    # ns.PartyBuffRow() with bigMyAuras: two lines of 18 px + gap, plus 3
    buff_row = PARTY_BIG_LINES * PARTY_BUFF_BIG + (PARTY_BIG_LINES - 1) * PARTY_GAP + 3
    step = ph + PARTY_FRAME_GAP + buff_row
    holder_h = 4 * ph + 3 * (PARTY_FRAME_GAP + buff_row)
    hx, hy = pos["party"][0] - psz["w"] / 2, pos["party"][1] + holder_h / 2
    members = [
        dict(cls="PALADIN", hp=1.0, pp=0.86, pc=MANA, lvl="13", leader=True, deb=[], buffs=["fort", "arcane"]),
        dict(cls="MAGE", hp=0.63, pp=0.42, pc=MANA, lvl="12", deb=[("poison", DISPEL["Poison"], "2")], glow=DISPEL["Poison"],
             after=[(0.12, HEAL_MINE), (0.08, HEAL_OTHER)], buffs=["fort"]),
        dict(cls="PRIEST", hp=0.88, pp=0.57, pc=MANA, lvl="12", deb=[("frost", DISPEL["Magic"], None)], buffs=["fort", "arcane"]),
        dict(cls="ROGUE", hp=1.0, pp=0.9, pc=ENERGY, lvl="11", deb=[], alpha=0.45, buffs=["fort"]),
    ]
    party_y = []
    for i, m in enumerate(members):
        cy = hy - i * step - ph / 2
        party_y.append(cy)
        cx = hx + psz["w"] / 2
        place("party", cx, cy, dict(id=f"party{i + 1}", accent=accent, level=m["lvl"], levelColor=PLAYER_LEVEL, name=t["party"][i],
                                    hp=m["hp"], hpColor=CLASS[m["cls"]], hpText=f"{round(m['hp'] * 100)}%", pp=m["pp"], ppColor=m["pc"],
                                    leader=m.get("leader"), dispelGlow=m.get("glow"), alpha=m.get("alpha", 1),
                                    after=m.get("after", ())))
        for j, (kind, border, cnt) in enumerate(m["deb"]):
            parts.append(aura(psz["w"] + 4 + j * (PARTY_SIZE + PARTY_GAP), (ph - PARTY_SIZE) / 2, PARTY_SIZE, kind, border, cnt, .85))
        # buff row 3 below the frame: my buffs (18, gold) first, then the others (16)
        bx = 0
        for kind in ["wild"]:
            parts.append(aura(bx, ph + 3, PARTY_BUFF_BIG, kind, accent, alpha=m.get("alpha", 1)))
            bx += PARTY_BUFF_BIG + PARTY_GAP
        for kind in m["buffs"]:
            parts.append(aura(bx, ph + 3, PARTY_BUFF_SIZE, kind, BUFF_BORDER, alpha=m.get("alpha", 1)))
            bx += PARTY_BUFF_SIZE + PARTY_GAP
        close()

    # nameplates (Modules/Nameplates.lua): 120 x 10
    def plate(cx, cy, name, level, lvl_color, color, frac, alpha, target=False, quest=False, debuffs=(), cast=None):
        Wp, Hp = 120, 10
        x0, y0 = X(cx) - Wp * S / 2, Y(cy) - Hp * S / 2
        q = []
        q.append(box(0, 0, Wp, Hp, f"background:{css(st['barBg'])};border:{px(1)} solid #000",
                     f'<div class="abs" style="left:0;top:0;bottom:0;width:{frac * 100:.1f}%;background:{css(color, 1)}"></div>'))
        if target:
            q.append(box(-2, -2, Wp + 4, Hp + 4, f"border:{px(1)} solid {css(accent)}"))
        q.append(text(Wp / 2, Hp / 2, f"{round(frac * 100)}%", 8, "#fff", anchor="center"))
        q.append(text(-3, Hp / 2, level, 10, css(lvl_color), anchor="right"))
        name_cy = -3 - 6
        q.append(text(Wp / 2, name_cy, name, 10, "#fff", anchor="center"))
        n = len(debuffs)
        tot = n * 18 + max(0, n - 1) * 2
        for k, (kind, cnt, sw) in enumerate(debuffs):
            q.append(aura(Wp / 2 - tot / 2 + k * 20, name_cy - 6 - 2 - 18, 18, kind, accent, cnt, swipe=sw))
        if target:
            q.append(f'<div class="abs" style="left:{px(Wp + 4)};top:{px(Hp / 2 - 9)}">{skull(18)}</div>')
        if cast:
            q.append(castbar(11, Hp + 3, Wp - 11, 9, cast[1], st["castbar"], cast[0], "", st, small=True, kick=L["kickLabel"]))
        parts.append(f'<div class="abs" style="left:{x0:.1f}px;top:{y0:.1f}px;width:{px(Wp)};height:{px(Hp)};opacity:{alpha}">{"".join(q)}</div>')
        if quest:  # on the default plate itself, not faded
            off = (18 + 4) if debuffs else 2
            qy = Y(cy) - Hp * S / 2 + (name_cy - 6 - off - 18) * S
            parts.append(f'<div class="t" style="left:{X(cx):.1f}px;top:{qy:.1f}px;transform:translate(-50%,0);font-size:{px(19)};'
                         f'font-weight:900;color:#ffd200;line-height:{px(18)};-webkit-text-stroke:{px(1.2)} #3a2600;{OUTLINE}">!</div>')
        rects[name] = (x0, y0, Wp, Hp)

    plate(-120, 150, t["boar"], "9", DIFF_GREEN, NEUTRAL, 1.0, 0.6, quest=True)
    plate(200, 90, t["target"], "13", DIFF_YELLOW, PLATE_THREAT_2, 0.64, 1, target=True,
          debuffs=[("moon", None, 40), ("claw", None, 65)], cast=(t["castTarget"], 0.62))

    # friendly nameplate, default "name only": class-coloured name, party member +2 size, no bar
    parts.append(f'<div class="t" style="left:{X(140):.1f}px;top:{Y(226):.1f}px;transform:translate(-50%,-50%);'
                 f'font-size:{px(12)};color:{css(CLASS["PALADIN"], 1)};{OUTLINE}">{t["party"][0]}</div>')

    # callouts (page px)
    def c(x, y):
        return (X(x), Y(y))
    calls = [
        c(-330, -150),   # 1 player
        c(10, -185),     # 2 energy spark
        c(10, -222),     # 3 combo / mana
        c(-180, -240),   # 4 player auras
        c(352, -190),    # 5 target
        c(120, -105),    # 6 target castbar
        c(215, -218),    # 7 target auras
        c(420, -120),    # 8 tot
        c(-302, 40),     # 9 focus
        c(-420, -215),   # 10 pet
        c(-318, 250),    # 11 party
        c(-60, 178),     # 12 quest
        c(310, 90),      # 13 target plate
        c(292, -214),    # 14 hit trail on the target (below its health bar)
        c(-534, party_y[1]),  # 15 heal prediction on a party member
        c(205, 226),     # 16 friendly nameplate
    ]
    for i, (x, y) in enumerate(calls, 1):
        parts.append(f'<div class="call" style="left:{x - 15:.0f}px;top:{y - 15:.0f}px">{i}</div>')

    notes_top = gy0 + (TOP - BOTTOM) * S + 30
    half = 8

    def note_html(start, lst):
        return "".join(f'<div class="note"><span class="n">{start + i}</span><div><b>{a}</b> — {b}</div></div>' for i, (a, b) in enumerate(lst))
    parts.append(f'<div class="notes" style="left:50px;top:{notes_top:.0f}px;width:720px">{note_html(1, t["notes"][:half])}</div>')
    parts.append(f'<div class="notes" style="left:820px;top:{notes_top:.0f}px;width:730px">{note_html(half + 1, t["notes"][half:])}</div>')
    page_h = notes_top + max(notes_height(t["notes"][:half], 690), notes_height(t["notes"][half:], 690)) + 60
    parts.append(f'<div class="abs foot" style="left:50px;top:{page_h - 40:.0f}px">{t["foot"]}</div>')
    head = f'<div class="page"><h1>EzWoW - Unit Frames</h1><div class="lead">{t["lead"]}</div></div>'
    return head + "".join(parts), page_h


# ---------------------------------------------------------------------------
# Settings window (UI/OptionsWindow.lua, 460 x 1012)
# ---------------------------------------------------------------------------
def settings_page(lang, ctx):
    global S
    S = 1.22
    t, L, st, dflt = T[lang], ctx["L"][lang], ctx["style"], ctx["defaults"]
    W, H = 460, 1012
    ox, oy = 60, 160
    p = []
    accent_c = css(st["accent"])
    body_c = css(st["textBody"])
    muted_c = css(st["textMuted"])

    def btn(x, y, w, h, label, accent=False, size=12):
        bg = css(st["bgAccent"]) if accent else css(st["bgSecondary"])
        bd = accent_c if accent else css(st["border"])
        col = accent_c if accent else body_c
        return box(x, y, w, h, f"background:{bg};border:{px(1)} solid {bd};display:flex;align-items:center;justify-content:center",
                   f'<span class="fit" data-fit="{(w - 10) * S:.1f}" style="font-size:{px(size)};color:{col};white-space:nowrap;{OUTLINE}">{label}</span>')

    # header (UIKit:CreateHeader)
    p.append(box(1, 1, W - 2, 58, f"background:{css(st['bgSecondary'], .98)}"))
    p.append(box(1, 57, W - 2, 2, f"background:{accent_c}"))
    p.append(f'<img class="abs" src="{ctx["icon"]}" style="left:{px(15)};top:{px(15)};width:{px(28)};height:{px(28)}">')
    p.append(f'<div class="t" style="left:{px(49)};top:{px(12)};font-size:{px(16)};color:{accent_c};{OUTLINE}">{ctx["title"]}</div>')
    p.append(f'<div class="t" style="left:{px(49)};top:{px(33)};font-size:{px(10)};color:{muted_c};{OUTLINE}">{L["settingsSub"]}</div>')
    p.append(btn(W - 1 - 10 - 22, 11, 22, 22, "X"))

    secs = []

    def section(key, y):
        p.append(f'<div class="t" style="left:{px(20)};top:{px(y)};font-size:{px(13)};color:{accent_c};{OUTLINE}">{L[key]}</div>')
        p.append(box(20, y + 20, W - 40, 1, f"background:{css(st['border'], .85)}"))
        secs.append(y)

    def check(x, y, label, on):
        mark = (f'<div class="t" style="left:{px(3)};top:{px(-2)};font-size:{px(22)};color:#ffd200;'
                f'text-shadow:0 0 1px #000,1px 1px 0 #6b4a00">✔</div>') if on else ""
        p.append(box(x + 3, y + 3, 18, 18, "border:1px solid #6d6a5d;background:#191919;border-radius:2px;overflow:visible", mark))
        p.append(f'<div class="t" style="left:{px(x + 28)};top:{px(y + 12)};transform:translate(0,-50%);font-size:{px(12)};color:{body_c};{OUTLINE}">'
                 f'<span class="fit" data-fit="{180 * S:.1f}" data-min="{9 * S:.1f}">{label}</span></div>')

    section("secFrames", 70)
    for i, key in enumerate(ctx["frameKeys"]):
        col, row = i % 3, i // 3
        check(20 + col * 140, 94 + row * 26, L[key], True)
    section("secDisplay", 160)
    L1, L2 = 20, 236
    rows = [("classColor", "portraits"), ("targetCastbar", "focusCastbar"), ("targetAuras", "onlyMyDebuffs"),
            ("comboPoints", "druidMana"), ("partyDebuffs", "rangeFade"), ("threatBorder", "partyInRaid"),
            ("hideBlizzard", "playerAuras"), ("powerTicks", "healthFX"), ("hitFX", "partyBuffs"),
            ("healPrediction", "bigMyAuras"), ("partyHorizontal", None)]
    for r, (a, b) in enumerate(rows):
        check(L1, 184 + r * 26, L["opt_" + a], dflt[a])
        if b:
            check(L2, 184 + r * 26, L["opt_" + b], dflt[b])
    section("secPlates", 482)
    prow = [("nameplates", "plateCastbar"), ("plateDebuffs", "plateThreat"), ("plateTankMode", "plateFadeOthers"), ("plateQuest", "kickWarn"),
            ("kickTargetOnly", "kickSound")]
    for r, (a, b) in enumerate(prow):
        check(L1, 506 + r * 26, L["opt_" + a], dflt[a])
        if b:
            check(L2, 506 + r * 26, L["opt_" + b], dflt[b])
    # friendly plates picker (default "name") and the instance option
    p.append(btn(L1, 637, 205, 24, f'{L["friendlyPlates"]}: {L["friendly_" + ctx["friendlyMode"]]} ▼', size=11))
    check(L2, 636, L["opt_friendlyHideInstance"], dflt["friendlyHideInstance"])

    def stepper(label, y_label, y_btn, value):
        p.append(f'<div class="t" style="left:{px(24)};top:{px(y_label)};font-size:{px(12)};color:{body_c};{OUTLINE}">'
                 f'<span class="fit" data-fit="{120 * S:.1f}" data-min="{9 * S:.1f}">{label}</span></div>')
        p.append(btn(150, y_btn, 27, 27, "-", size=16))
        p.append(text(150 + 27 + 4 + 26, y_btn + 13.5, value, 12, body_c, anchor="center"))
        p.append(btn(150 + 27 + 60, y_btn, 27, 27, "+", size=16))
    stepper(L["plateScale"], 672, 665, "100%")
    section("secText", 700)
    for x, lk, mode in ((20, "textBig", "curpct"), (162, "textSmall", "percent"), (304, "textParty", "percent")):
        p.append(f'<div class="t" style="left:{px(x + 2)};top:{px(726)};font-size:{px(11)};color:{muted_c};{OUTLINE}">'
                 f'<span class="fit" data-fit="{128 * S:.1f}" data-min="{8 * S:.1f}">{L[lk]}</span></div>')
        p.append(btn(x, 742, 132, 26, L["text_" + mode] + " ▼", size=11))
    section("secLayout", 784)
    stepper(L["scale"], 818, 811, "100%")
    p.append(btn(20, 848, 205, 32, L["unlock"], accent=True))
    p.append(btn(235, 848, 205, 32, L["resetPos"]))
    p.append(btn(20, 888, 205, 28, f'{L["language"]}: Auto ▼'))
    p.append(btn(235, 888, 205, 28, L["donate"], accent=True))
    p.append(f'<div class="abs" style="left:{px(22)};top:{px(928)};width:{px(416)};font-size:{px(10.5)};line-height:1.35;color:{muted_c};{OUTLINE}">{L["hint"]}</div>')
    p.append(f'<div class="t" style="left:{px(W / 2)};top:{px(H - 18)};transform:translate(-50%,0);font-size:{px(10)};color:#808080">'
             f'{ctx["title"]}{" v" + ctx["version"] if ctx["version"] else ""}  ·  /ezuf</div>')

    win = (f'<div class="abs" style="left:{ox}px;top:{oy}px;width:{px(W)};height:{px(H)};background:{css(st["bgPrimary"])};'
           f'border:1px solid {css(st["border"])}">' + "".join(p) + "</div>")
    spans = [(secs[0], secs[1]), (secs[1], secs[2]), (secs[2], secs[3]), (secs[3], secs[4]), (secs[4], 952)]
    calls = "".join(f'<div class="call" style="left:{ox + W * S + 18:.0f}px;top:{oy + (a + b) / 2 * S - 15:.0f}px">{i}</div>'
                    for i, (a, b) in enumerate(spans, 1))
    notes = "".join(f'<div class="note"><span class="n">{i}</span><div><b>{a}</b> — {b}</div></div>' for i, (a, b) in enumerate(t["sNotes"], 1))
    page_h = oy + H * S + 80
    nx = ox + W * S + 80
    body = (f'<div class="page"><h1>EzWoW - Unit Frames <span class="badge">{t["sTitle"]}</span></h1>'
            f'<div class="lead">{t["sLead"]}</div></div>' + win + calls
            + f'<div class="notes" style="left:{nx:.0f}px;top:{oy + 10}px;width:{PAGE_W - nx - 50:.0f}px">{notes}</div>'
            + f'<div class="abs foot" style="left:50px;top:{page_h - 44:.0f}px">{t["sFoot"]}</div>')
    return body, page_h


# ---------------------------------------------------------------------------
SHADE = ('<svg width="0" height="0" style="position:absolute"><defs><linearGradient id="shade" x1="0" y1="0" x2="1" y2="1">'
         '<stop offset="0" stop-color="#fff" stop-opacity=".18"/><stop offset=".55" stop-color="#000" stop-opacity="0"/>'
         '<stop offset="1" stop-color="#000" stop-opacity=".35"/></linearGradient></defs></svg>')


def find_chrome():
    cands = [os.environ.get("CHROME"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
             shutil.which("chrome"), shutil.which("google-chrome"), shutil.which("chromium")]
    for c in cands:
        if c and Path(c).exists():
            return c
    sys.exit("Chrome not found (set CHROME=<path to chrome>)")


def render(chrome, html, out_png, height, tmp):
    page = Path(tmp) / (out_png.stem + ".html")
    page.write_text(html, encoding="utf-8")
    subprocess.run([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--user-data-dir={Path(tmp) / 'chrome_profile'}", f"--window-size={PAGE_W},{int(height)}",
                    "--virtual-time-budget=2000", f"--screenshot={out_png}", page.as_uri()],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main(root: Path):
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    init = read(root, "Core/Init.lua")
    locales = read(root, "Core/Locales.lua")
    ctx = {
        "sizes": parse_sizes(read(root, "Modules/UnitButton.lua")),
        "style": parse_style(init),
        "defaults": parse_defaults(init),
        "friendlyMode": re.search(r'^\s*friendlyPlates\s*=\s*"(\w+)"', init, re.M).group(1),
        "L": {"ko": parse_locale(locales, "koKR"), "en": parse_locale(locales, "enUS")},
        "title": re.search(r'ns\.TITLE\s*=\s*"([^"]+)"', init).group(1),
        "version": parse_version(read(root, "EzWoW-UnitFrames.toc")),
        "frameKeys": re.findall(r'"(\w+)"', re.search(r"ns\.FRAME_KEYS\s*=\s*\{([^}]*)\}", init).group(1)),
        "icon": "data:image/png;base64," + base64.b64encode((root / "Media" / "Icon.png").read_bytes()).decode(),
    }
    chrome = find_chrome()
    tmp = tempfile.mkdtemp(prefix="ezuf_readme_")
    try:
        for lang in ("ko", "en"):
            for name, fn in (("ui", ui_page), ("settings", settings_page)):
                body, h = fn(lang, ctx)
                html = (f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head>'
                        f'<body style="height:{int(h)}px">{SHADE}{body}{FIT_JS}</body></html>')
                png = out / f"{name}_{lang}.png"
                render(chrome, html, png, h, tmp)
                print("wrote", png, int(h))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())
