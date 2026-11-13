# v1.0.9

### 한국어
- 데이터 공유 현황 창을 추가했습니다. `/공유` 또는 `/ezshare`로 열면 받은 기록, 보낸 사람, 보낸 기록, 종류별 현황과 새로 받은 기록만 따로 볼 수 있습니다.
- 공유 데이터를 채널로도 보내 더 빨리 퍼지게 했습니다.
- 데이터 채널의 사용자 명단이 새로 갱신되지 않아 일부 사용자와 귓속말로 공유 기록을 주고받지 못하던 문제를 고쳤습니다.
- 퀘스트 보상, 트레이너가 가르치는 주문, 오브젝트 이름도 다른 사용자와 공유합니다.
- 대상·주시 대상 버프·디버프를 켜 두면 "내 캐릭터 버프·디버프"를 꺼도 내 버프가 계속 보이던 문제를 고쳤습니다.
- 화면이 작거나 UI 크기가 클 때 설정 창 아래쪽이 화면 밖으로 나가던 문제를 고쳤습니다. 창이 화면에 맞게 줄어듭니다.
- 게임패드: 전투가 끝나면 EzWoW 창이 패드 조작을 가져가던 문제를 고쳤습니다. 전투 전에 EzWoW 창을 조작하던 경우에만 되돌립니다.
- 대상 프레임을 옮기면 대상의 대상 프레임이, 내 캐릭터 프레임을 옮기면 소환수 프레임이 같이 따라옵니다.
- 공유 기록을 설치된 EzWoW 애드온 중 최대 2개에만 저장해 접속·다시 불러오기가 빨라지고 저장 파일이 작아집니다. 업데이트 후 게임을 한 번 완전히 다시 시작하면 적용됩니다.

### English
- Added a data sharing window. Open it with `/ezshare` to see received records, players, sent records, totals by kind, and only the newly received records.
- Shared data is now also sent through the channel, so it spreads faster.
- Fixed shared records not being exchanged by whisper with some players because the data channel's player list was not refreshed.
- Quest rewards, trainer spells and object names are now shared with other players too.
- Fixed "Player buffs & debuffs" not hiding your auras while target and focus auras were on.
- The settings window now shrinks to fit small screens and large UI scales, so its lower part is no longer off-screen.
- Gamepad: EzWoW windows no longer take over the pad after combat; it returns only if you were using an EzWoW window before the fight.
- Moving the target frame now moves the target-of-target frame along, and moving the player frame moves the pet frame.
- Shared records are now saved by at most 2 of your installed EzWoW addons, so logins and reloads are faster and save files smaller. Takes effect after one full game restart following the update.
