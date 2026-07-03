# claude-issue-triage

**GitHub 이슈를 Claude Code가 매일 자동으로 트리아지하는 킷** — 단순한 이슈는 스스로 고쳐서
커밋·push·close까지, 판단이 필요한 이슈는 옵션 A/B/C를 정리한 코멘트만 남기고 담당자의 결정을 기다립니다.

실제 서비스 운영 저장소에서 이슈 #1~#11을 처리하며 검증된 워크플로를 그대로 추출했습니다
(무인 인증 만료, 사내 프록시 TLS, GitHub 간헐 장애 같은 실전 문제의 해법 포함).

```
[매일 10:00 예약 실행 — 무인]
   ├─ 이슈 없음   → 로그만 남기고 종료
   ├─ 단순 수정   → 코드 수정 + 검증 + commit(이슈별) ──┐
   └─ 판단 필요   → 코드/커밋 없이 옵션 A/B/C 코멘트만    │
      (run 끝에)  커밋들을 [모아서] push 1회 ────────────┴→ 각 이슈에 완료 코멘트 + close

[사람이 결정할 때 — 대화형]
   /session-briefing        ← 세션 열면 자동 브리핑: 판단 대기 이슈 + 옵션 + 추천안
   /resolve-issue 15 B      ← 한 줄로 결정 → 구현 → 배치 push → 완료 코멘트 + close
```

## 왜 이 방식인가

- **자동화의 경계가 명확** — "애매하면 판단 필요"가 기본값. 봇은 판단 필요 이슈에 코드도 커밋도
  만들지 않고, 옵션(장단점·추천안)만 정리합니다. 사람은 아침에 브리핑 보고 `/resolve-issue 15 B` 한 줄.
- **크래시-세이프** — 완료 코멘트·close는 **push 성공 후에만**. 어느 시점에 끊겨도 거짓 상태가 남지 않고
  다음 실행이 미완 마감을 재개합니다.
- **되돌리기 쉬움** — 한 이슈 = 한 커밋. 문제가 된 자동 수정은 `git revert <해시>` 하나로 원복.
- **3겹 안전장치** — `dontAsk` 권한 모드 + settings.json deny/allow + 명령 토큰화 훅(`guard.js`)이
  force push·타 원격 push·재귀 삭제·`reset --hard`를 플래그 위치와 무관하게 차단.
- **CI·배포 절약** — push는 run당 1회 배치(커밋 해시가 이슈를 구분).

## 설치 (프로젝트 루트에서)

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/kiminyeob/claude-issue-triage/main/install.ps1 | iex
```

```bash
# macOS / Linux / Git Bash
curl -fsSL https://raw.githubusercontent.com/kiminyeob/claude-issue-triage/main/install.sh | bash
```

설치 후 3분 설정:

```text
1. .claude/commands/issue-triage.md 상단 ✏️ 블록 편집  (검증 명령·프로젝트 원칙)
2. .claude/CLAUDE-md-snippet.md → 프로젝트 CLAUDE.md에 붙여넣기
3. claude setup-token → 토큰을 .claude/automation/oauth-token.secret 에 저장  (무인 인증)
4. 스케줄 등록:
     Windows:      powershell -File .\.claude\automation\register-task.ps1
     macOS/Linux:  bash .claude/automation/register-cron.sh
```

전체 절차는 [docs/setup.md](docs/setup.md), 첫 실행 확인·문제 해결은 [docs/troubleshooting.md](docs/troubleshooting.md).

## 필요한 것

[Claude Code](https://claude.com/claude-code) · [GitHub CLI](https://cli.github.com/)(`gh auth login`) · git · Node.js
— 대상 프로젝트는 `origin` 원격이 연결된 git 저장소(기본 브랜치 직접 커밋 전략, 1인·소규모 프로젝트에 적합).

## 무엇이 설치되나

| 파일 | 역할 |
|---|---|
| `.claude/commands/issue-triage.md` | 트리아지 본체 — 분류 기준·처리 절차·코멘트 템플릿·멱등성 규칙 |
| `.claude/commands/session-briefing.md` | 대화형 세션 시작 브리핑(판단 대기·미push 재개) |
| `.claude/commands/resolve-issue.md` | 판단 대기 이슈를 지정 옵션으로 구현·마감 |
| `.claude/automation/run-triage.ps1` / `.sh` | 예약 실행 래퍼 — 인증 토큰 주입·프록시 CA·로그 수집 |
| `.claude/automation/register-task.ps1` / `register-cron.sh` | 스케줄 등록(작업 스케줄러 / crontab) |
| `.claude/automation/guard.js` | PreToolUse 훅 — 파괴적 git/셸 명령 토큰화 차단 |
| `.claude/settings.json` | 권한 allow/deny + 훅 배선(기존 파일은 건드리지 않고 제안본 생성) |
| `.claude/CLAUDE-md-snippet.md` | 프로젝트 CLAUDE.md에 붙여넣는 운영 거버넌스 블록 |

동작 원리(SSOT·멱등성·배치 push·안전 계층)는 [docs/how-it-works.md](docs/how-it-works.md),
분류 기준·모델·템플릿 수정은 [docs/customization.md](docs/customization.md).

## 문서

- [설치·설정 (setup.md)](docs/setup.md)
- [커스터마이징 (customization.md)](docs/customization.md)
- [동작 원리 (how-it-works.md)](docs/how-it-works.md)
- [트러블슈팅 (troubleshooting.md)](docs/troubleshooting.md) — 무인 401, 사내 프록시 TLS, cron 미실행 등

## 주의

- 자동 push는 **단순 수정 커밋에 한해, 현재 브랜치 → `origin`으로만** 일어납니다. 그래도 무인 자동 커밋이
  부담스러운 저장소(다인 협업·보호 브랜치)에는 붙이지 마세요 — 이 킷은 기본 브랜치 직접 커밋 전략 전제입니다.
- 봇 코멘트 헤더 문자열(`✅ 자동으로 처리되었습니다` / `🔍 검토가 필요합니다`)은 멱등성 신호입니다.
  바꾸려면 [customization.md](docs/customization.md#코멘트-템플릿언어)를 먼저 읽으세요.

---

## English summary

**claude-issue-triage** is a kit that lets [Claude Code](https://claude.com/claude-code) triage your
GitHub issues on a daily schedule, unattended: trivial fixes are implemented, verified, committed and
batch-pushed with the issue auto-closed; anything requiring judgment gets an options comment
(A/B/C with trade-offs and a recommendation) and stays open for a human decision — which you execute
later with a single `/resolve-issue 15 B`.

Extracted from a workflow battle-tested on a production repo (11 issues processed), including fixes for
real unattended-operation problems: nightly OAuth expiry (`claude setup-token` injection), corporate
TLS-intercepting proxies (`NODE_EXTRA_CA_CERTS` bundle), and crash-safe batch closing (close only after
push succeeds).

**Install** (from your project root): see the one-liners above. **Safety:** three defense layers
(`dontAsk` permission mode, settings deny-list, and a tokenizing PreToolUse hook that blocks force
pushes, foreign remotes and recursive deletes regardless of flag position). One issue = one commit
(clean `git revert`), pushes batched once per run. Docs are currently Korean-first; the command files
drive the bot's GitHub comments in Korean — translate the templates in
`.claude/commands/issue-triage.md` if you want English comments (keep the idempotency headers in sync,
see [customization](docs/customization.md)).

## License

[MIT](LICENSE)
