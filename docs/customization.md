# 커스터마이징 가이드 (Customization)

모든 동작 정의는 **마크다운·스크립트 파일**입니다 — 코드 빌드 없이 파일을 고치면 다음 실행부터 적용됩니다.

## 검증 명령 (필수 설정)

트리아지는 수정 후 프로젝트 검증을 돌리고, **실패하면 push하지 않고 "판단 필요"로 강등**합니다.
두 곳을 함께 수정하세요:

1. **`.claude/commands/issue-triage.md` 상단 ✏️ 블록** — 실행할 명령 목록.
2. **`.claude/settings.json` `permissions.allow`** — 그 명령들의 allow 항목.
   템플릿에는 pnpm/npm/yarn의 `typecheck`/`lint`/`test`/`build`가 미리 들어 있습니다.
   다른 러너(cargo, go, gradle...)면 같은 형식으로 추가:
   ```json
   "Bash(cargo test:*)",
   "Bash(go test:*)"
   ```
   > allow에 없는 명령은 헤드리스(dontAsk)에서 조용히 거부됩니다 — 검증이 실패한 것으로 취급되어
   > 판단 필요로 넘어가니, 안전하지만 자동 처리율이 떨어집니다.

## 분류 기준 (단순 수정 vs 판단 필요)

`.claude/commands/issue-triage.md` §4가 기준 전문입니다. 팀 성격에 맞게 목록을 조정하세요.
**"애매하면 판단 필요"** 원칙은 유지를 권장합니다 — 자동 실행의 안전 경계는 보수적 분류에서 나옵니다.

프로젝트 고유 원칙(예: 디자인 토큰만 사용, 특정 디렉터리 불가침)은 ✏️ 블록에 적으면
"단순 수정이라도 원칙 위반이면 판단 필요로 강등"이 함께 적용됩니다.

## 모델·시각

- **모델(예약 실행):** `run-triage.ps1`의 `$TriageModel` / `run-triage.sh`의 `TRIAGE_MODEL` (기본 `claude-sonnet-5`).
  대화형 실행은 그 세션의 모델을 그대로 씁니다.
- **시각:** 등록 스크립트 인자 — `register-task.ps1 -At '09:30'` / `register-cron.sh 09:30`.

## 코멘트 템플릿·언어

봇이 이슈에 남기는 [템플릿 1·2·3]은 `issue-triage.md` 하단에 전문이 있습니다(3은 `resolve-issue.md`에도).
문구·언어를 자유롭게 바꾸되 **헤더 문자열은 멱등성 신호**입니다:

- `✅ 자동으로 처리되었습니다` / `🔍 검토가 필요합니다` — 다음 실행이 "이미 처리된 이슈"를 판별하는
  1차 신호이므로, 바꾸려면 §3(멱등성 체크)의 매칭 문자열도 **함께** 바꾸세요.

## push 정책

기본값은 **배치 push**입니다: 이슈별 커밋(revert 단위)은 유지하되, push는 run/세션당 한 번으로 모아
재배포·CI를 1회로 줄입니다. close·완료 코멘트는 push 성공 후 일괄 — 이 **불변식은 유지"를 강력히 권장**합니다
(원격에 없는 커밋을 "완료"로 표시하는 거짓 상태 방지).

이슈마다 즉시 push하는 예전 방식으로 돌리려면 `issue-triage.md` §5·§6.5와 `resolve-issue.md` 4~6단계를
"커밋 직후 push → 코멘트 → close"로 다시 합치면 됩니다.

## 안전 계층 (완화하기 전에 읽기)

방어는 3겹입니다:

1. **`--permission-mode dontAsk`** — 예약 실행에서 확인 프롬프트가 뜰 상황이면 기본 거부. Write 도구 전면 차단.
2. **`settings.json` deny** — force push·reset --hard·재귀 삭제·원격 변경·네트워크 유출 명령 등 접두사 차단.
3. **`guard.js` (PreToolUse 훅)** — 명령을 셸처럼 토큰화해 **플래그 위치와 무관하게** 재검사
   (deny는 접두사만 보므로 `git push origin main --force` 같은 후치 플래그를 놓침 — 이걸 잡는 층).
   `origin` 외 원격 push, `+refspec` 강제 push, PowerShell 재귀 삭제까지 차단.

allow를 넓힐 때는 "그 명령이 headless에서 무엇을 할 수 있는가"를 기준으로 판단하세요.
`Bash(npm run:*)`처럼 임의 스크립트 실행을 통째로 여는 패턴은 권장하지 않습니다(스크립트에 뭐든 들어갈 수 있음).

## 여러 프로젝트에 설치

각 프로젝트마다 설치기를 실행하면 됩니다. 작업 스케줄러 작업명(`IssueTriage-<폴더명>`)과
cron 마커(`# claude-issue-triage:<폴더명>`)가 프로젝트별로 분리되어 공존합니다.
