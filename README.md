# EzWoW - Unit Frames

내 캐릭터·대상·대상의 대상·주시 대상·소환수·파티 체력바와 적 이름표를 깔끔한 EzWoW 스타일로 바꿉니다.
Clean EzWoW-style player, target, target of target, focus, pet and party frames, plus enemy nameplates.

- 명령어 / Commands: `/ezuf`, `/유닛프레임` (`/ezuf 이동` · `/ezuf 잠금` · `/ezuf 초기화`)

## 한국어

### 화면 미리보기

![유닛 프레임과 이름표](https://raw.githubusercontent.com/qqhrqqhr2/EzWoW-UnitFrames/master/docs/images/ui_ko.png)

![설정창](https://raw.githubusercontent.com/qqhrqqhr2/EzWoW-UnitFrames/master/docs/images/settings_ko.png)

> 애드온 코드의 프레임 크기·색상·문구로 재현한 **예시 화면**입니다. 프레임 간격은 그림에 맞게 좁혔고, 초상화·아이콘은 단순화했으며, 이름은 지어낸 예시입니다.

### 프레임
- 내 캐릭터 · 대상 · 대상의 대상 · 주시 대상 · 소환수 · 파티(4명). 각각 켜고 끌 수 있습니다.
- 왼쪽 클릭은 대상 선택, 오른쪽 클릭은 메뉴입니다. 마우스를 올리면 툴팁이 나옵니다.

### 편의 기능
- 직업 색 체력바, 체력 글자 형식 선택(현재 · %, 현재 / 최대, 현재, %, 부족량)
- **기력 틱·마나 5초 규칙**: 기력 바 위의 불꽃이 2초 기력 틱을 따라갑니다. 마나를 쓰면 금색 불꽃이 5초를 센 뒤 2초 마나 틱을 보여 줍니다.
- 대상·주시 대상 시전바 (차단할 수 없는 주문은 회색 + 방패 표시, 차단되면 "차단됨")
- 대상 버프·디버프 (내가 건 것은 금색 테두리, 내 디버프만 보기 옵션), 내 캐릭터 버프·디버프
- 연계 점수(도적·드루이드), 변신 중 드루이드 마나
- 파티원 버프 줄(체력바 아래)·디버프 아이콘과 내가 해제할 수 있는 디버프 테두리 표시, 사거리 밖 파티원 흐리게
- **체력바 효과**: 광택·전투 중 맥동·낮은 체력 경고, 맞을 때 빨간 잔상과 번쩍임, 회복 때 초록 잔상
- 위협 수준 테두리, 공격대 징표·파티장·전투·휴식 아이콘, 정예·희귀 표시

### 이름표 (적 머리 위 체력바)
- 위협 수준 색(딜러 기준 / 탱커 기준), 시전바(차단 불가 표시), 내가 건 디버프, 레벨·정예 표시, 공격대 징표
- **퀘스트 몹 표시**: 퀘스트 목표인 적의 이름표 위에 "!"가 나타납니다.
- 현재 대상은 테두리 강조, 대상이 아닌 이름표는 흐리게, 이름표 크기 조절
- 게임 기본 이름표의 위치·클릭은 그대로 두고 모양만 바꿉니다. 아군 이름표는 기본 모양을 유지합니다.

### 위치·크기
- 설정에서 **잠금 해제**를 누르면 모든 프레임이 미리보기로 나타나고 끌어서 옮길 수 있습니다. 전투가 시작되면 자동으로 잠깁니다.
- 프레임 크기(60~160%), 위치 초기화, 기본 프레임 숨기기.

## English

### Screenshots

![Unit frames and nameplates](https://raw.githubusercontent.com/qqhrqqhr2/EzWoW-UnitFrames/master/docs/images/ui_en.png)

![Settings window](https://raw.githubusercontent.com/qqhrqqhr2/EzWoW-UnitFrames/master/docs/images/settings_en.png)

> These are **mock-ups** rebuilt from the frame sizes, colours and strings in the code. Spacing is tightened to fit, portraits and icons are simplified, and all names are made up.

### Frames
- Player, target, target of target, focus, pet and party (4). Each can be turned off.
- Left-click targets, right-click opens the menu, mouse-over shows the tooltip.

### Features
- Class-coloured health, health text formats (current · %, current / max, current, %, deficit)
- **Energy ticks & mana 5-second rule**: a spark on the energy bar follows the 2-second energy tick. After you spend mana, a gold spark counts the 5 seconds, then shows the 2-second mana ticks.
- Target and focus cast bars (uninterruptible casts are grey with a shield; "Interrupted" on kicks)
- Target buffs and debuffs (yours have a gold border; option to show only yours), player buffs and debuffs
- Combo points (rogue, druid) and druid mana while shapeshifted
- Party buff row (under the health bar) and debuff icons, a glow for debuffs you can dispel, faded out-of-range members
- **Health bar effects**: gloss, a combat pulse and low-health warning, a red trail and flash when hit, a green trail when healed
- Threat border, raid marker, leader, combat and resting icons, elite and rare tags

### Nameplates (enemies)
- Threat colours (DPS or tank view), cast bars (uninterruptible shown), your debuffs, level and elite tags, raid markers
- **Quest mob marker**: a "!" above enemies you need for a quest.
- The current target is outlined, other plates can fade, adjustable size
- The game's own plates keep their positions and clicks; only the look changes. Friendly plates stay default.

### Position & size
- **Unlock** in the settings shows every frame as a preview so you can drag it; frames lock again when combat starts.
- Frame size (60-160%), reset positions, hide the default frames.
