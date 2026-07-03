# 설치·설정 가이드 (Setup)

처음부터 끝까지: 설치 → 프로젝트 설정 → 인증 → 스케줄 등록 → 첫 실행 확인.

## 0. 사전 요구사항

| 도구 | 용도 | 확인 |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) | 트리아지 실행 주체 | `claude --version` |
| [GitHub CLI](https://cli.github.com/) | 이슈 조회·코멘트·close | `gh auth status` (로그인 필요) |
| git | 커밋·push | `git --version` |
| Node.js | `guard.js` 안전 훅 실행 | `node --version` |

대상 프로젝트는 **GitHub 원격(`origin`)이 연결된 git 저장소**여야 하며, 이 킷은 **기본 브랜치 직접 커밋** 전략을 가정합니다(PR 흐름 아님 — 1인·소규모 프로젝트에 적합).

## 1. 설치

**프로젝트 루트에서** 실행합니다:

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/kiminyeob/claude-issue-triage/main/install.ps1 | iex
```

```bash
# macOS / Linux / Git Bash
curl -fsSL https://raw.githubusercontent.com/kiminyeob/claude-issue-triage/main/install.sh | bash
```

설치되는 것:

```
your-project/
├─ .claude/
│  ├─ commands/
│  │  ├─ issue-triage.md        # 트리아지 본체(분류·처리·템플릿)
│  │  ├─ session-briefing.md    # 세션 시작 브리핑
│  │  └─ resolve-issue.md       # 판단 대기 이슈 결정 처리
│  ├─ automation/
│  │  ├─ run-triage.ps1 / .sh   # 예약 실행 래퍼 (Windows / macOS·Linux)
│  │  ├─ register-task.ps1      # Windows 작업 스케줄러 등록
│  │  ├─ register-cron.sh       # crontab 등록
│  │  └─ guard.js               # 파괴적 명령 차단 훅
│  ├─ settings.json             # 권한 allow/deny + 훅 (기존 파일 있으면 *-suggested.json)
│  └─ CLAUDE-md-snippet.md      # CLAUDE.md에 붙여넣을 거버넌스 블록
└─ .gitignore                   # 로컬 런타임 파일 제외 항목 추가됨
```

> 설치기는 **기존 파일을 절대 덮어쓰지 않습니다**(건너뛴 파일 목록 출력). 덮어쓰려면 `TRIAGE_FORCE=1`.

## 2. 프로젝트 설정 (2곳)

1. **`.claude/commands/issue-triage.md` 상단 ✏️ 블록** — 필수:
   - 검증 명령(typecheck/lint/test/build 등 — 프로젝트 러너에 맞게)
   - 프로젝트 고유 원칙(있으면)
2. **`.claude/CLAUDE-md-snippet.md`** 내용을 프로젝트 `CLAUDE.md`에 붙여넣기 — Claude가 세션 시작 시
   `/session-briefing`을 먼저 실행하고 운영 규칙(배치 push·절대 규칙)을 따르게 됩니다.

`settings.json`이 이미 있던 프로젝트는 `.claude/settings.triage-suggested.json`이 생성됩니다 —
`permissions.deny`/`allow`/`hooks`를 기존 파일에 병합하세요. (Claude Code에게 "settings.triage-suggested.json을
settings.json에 병합해줘"라고 시키는 게 가장 빠릅니다.)

## 3. 헤드리스 인증 — `claude setup-token` (중요)

예약(무인) 실행은 **대화형 로그인 토큰으로 오래 못 버팁니다** — 대화형 OAuth 액세스 토큰은 대략
하루 안에 만료되고, 헤드리스 실행은 이를 갱신하지 못해 다음 날 `401 Invalid authentication credentials`로
즉시 종료됩니다. 장기 토큰을 만들어 래퍼가 읽을 파일에 저장하세요:

```bash
claude setup-token
# 브라우저 인증 → sk-ant-oat... 토큰 출력
```

토큰을 프로젝트의 다음 파일에 **한 줄로** 저장(이 파일은 .gitignore에 이미 등록됨 — 커밋 안 됨):

```powershell
# Windows
Set-Content -Path ".\.claude\automation\oauth-token.secret" -Value "<토큰>" -NoNewline -Encoding ascii
```
```bash
# macOS / Linux
printf '%s' '<토큰>' > .claude/automation/oauth-token.secret
```

> 사내 SSL 검사 프록시 환경에서 `setup-token`이 `UNABLE_TO_VERIFY_LEAF_SIGNATURE`로 실패하면
> [troubleshooting.md](troubleshooting.md#사내-프록시-tls)를 보세요.

## 4. 스케줄 등록

**Windows (작업 스케줄러):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.claude\automation\register-task.ps1          # 매일 10:00
powershell -NoProfile -ExecutionPolicy Bypass -File .\.claude\automation\register-task.ps1 -At '09:30'
```
- 로그온 세션에서만 실행(비밀번호 저장 없음), 일반 권한, 놓친 실행 소급 없음(꺼져 있던 날은 스킵).

**macOS / Linux (cron):**
```bash
bash .claude/automation/register-cron.sh          # 매일 10:00
bash .claude/automation/register-cron.sh 09:30
```
- 재실행하면 기존 등록을 교체(멱등). macOS에서 cron 대신 launchd를 쓰려면 `run-triage.sh`를
  StartCalendarInterval로 감싸는 plist를 만들면 됩니다(래퍼는 그대로 재사용).

## 5. 첫 실행 확인

```powershell
# Windows — 즉시 실행
Start-ScheduledTask -TaskName "IssueTriage-<프로젝트폴더명>"
```
```bash
# macOS / Linux — 즉시 실행
bash .claude/automation/run-triage.sh
```

그런 다음 `.claude/automation/cron.log` 끝을 확인:

- `END (exit 0)` + `401`/`WARN` 없음 → 정상. (열린 이슈가 없으면 "이슈 없음"으로 끝나는 것이 정상 성공입니다.)
- 오류가 보이면 → [troubleshooting.md](troubleshooting.md)

## 6. 평소 사용법

| 상황 | 하는 일 |
|---|---|
| 매일 예약 시각 | 자동: 단순 수정은 커밋→배치 push→[템플릿1]+close, 판단 필요는 [템플릿2] 옵션 코멘트만 |
| 대화형 세션 시작 | Claude가 `/session-briefing` 자동 실행 — 판단 대기·미push를 브리핑 |
| 판단 대기 결정 | `/resolve-issue <번호> <옵션>` (예: `/resolve-issue 15 B`) |
| 예약 기다리기 싫을 때 | 대화형에서 `/issue-triage` — 예약과 완전히 같은 커맨드 |
