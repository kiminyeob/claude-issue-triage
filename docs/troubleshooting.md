# 트러블슈팅 (Troubleshooting)

실제 운영에서 겪고 해결한 순서대로 정리했습니다. 증상 → 원인 → 처방.

## 예약 실행이 10초 만에 죽음 — `401 Invalid authentication credentials`

```
===== [..] (scheduled) issue-triage START =====
Failed to authenticate. API Error: 401 Invalid authentication credentials
===== [..] issue-triage END (exit 1) =====
```

**원인:** 예약 실행이 대화형 로그인 토큰(`~/.claude/.credentials.json`)에 의존하고 있고,
그 액세스 토큰이 만료됨(대략 하루 수명). 무인 실행은 갱신하지 못합니다.
"어제는 됐는데 오늘 안 된다"가 전형적 증상입니다.

**처방:** 장기 토큰을 만들어 래퍼가 읽는 파일에 저장:

```bash
claude setup-token          # 브라우저 인증 → sk-ant-oat... 출력
```
```powershell
Set-Content -Path ".\.claude\automation\oauth-token.secret" -Value "<토큰>" -NoNewline -Encoding ascii
```

래퍼(`run-triage.ps1`/`.sh`)가 이 파일을 `CLAUDE_CODE_OAUTH_TOKEN`으로 주입합니다.
파일이 없으면 cron.log에 `[WARN] CLAUDE_CODE_OAUTH_TOKEN not set ...`이 남습니다 — 그 경고가 이 항목입니다.

## 예약 실행이 수십 분 돌다 죽음 — `Prompt is too long`

```
===== [..] (scheduled) issue-triage START =====
Prompt is too long
===== [..] issue-triage END (exit 1)  ← START로부터 10~30분 뒤
```

**원인:** 헤드리스 `claude -p` 세션은 대화형과 달리 **컨텍스트 자동 압축이 없습니다.**
세션이 읽은 것(긴 이슈 코멘트 스레드 전체, 큰 로컬 로그/이력 문서 통독, 난제 이슈의
깊은 코드 조사, 장황한 테스트 출력)이 전부 누적되고, 모델 컨텍스트 한도를 넘는 순간
run 전체가 저 한 줄을 남기고 죽습니다. "실행은 시작됐고 한참 돌다가 exit 1"이 전형적 증상입니다
(401처럼 즉사하지 않는 것이 구분점).

**처방:** 커맨드 문서의 **§0.5 컨텍스트 예산** 규칙이 이걸 막습니다(v1.1에서 신설) —
핵심은 ①이슈 코멘트를 `--jq` 헤더 카운트로만 확인(스레드 통째 로드 금지)
②`log.md`는 grep으로 해당 이슈 줄만 ③코드 조사는 Grep+부분 Read
④**딥다이브 컷**: 파일 3개 이상 열어야 하는 난제는 즉시 "판단 필요"로 넘기고 대화형에 맡김.
아울러 `log.md`가 ~30KB를 넘으면 오래된 항목을 `log-archive.md`로 이전하세요(§0.5-7).
구버전 템플릿을 쓰고 있다면 `template/.claude/commands/issue-triage.md`의 §0.5를 가져오면 됩니다.

<a id="사내-프록시-tls"></a>
## `setup-token`이 SSL 오류로 실패 — `UNABLE_TO_VERIFY_LEAF_SIGNATURE`

```
OAuth error: SSL certificate error (UNABLE_TO_VERIFY_LEAF_SIGNATURE).
If you are behind a corporate proxy or TLS-intercepting firewall, set NODE_EXTRA_CA_CERTS ...
```

**원인:** 사내 TLS 검사 프록시(Zscaler·Netskope·사내 CA 등)가 인증서를 바꿔치기하는데,
Claude Code가 도는 **Node.js는 OS 인증서 저장소를 쓰지 않고 자체 CA 목록만** 봅니다.
브라우저는 되는데 CLI만 실패하면 거의 이것입니다.

**처방 (Windows):** OS 저장소에서 PEM 번들을 만들어 `NODE_EXTRA_CA_CERTS`로 지정:

```powershell
# 1) Windows 인증서 저장소 → PEM 번들 (사내 프록시 CA 포함)
Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\CA, Cert:\CurrentUser\Root, Cert:\CurrentUser\CA -ErrorAction SilentlyContinue |
  Sort-Object Thumbprint -Unique | ForEach-Object {
    "-----BEGIN CERTIFICATE-----"
    [Convert]::ToBase64String($_.RawData, 'InsertLineBreaks')
    "-----END CERTIFICATE-----"
  } | Set-Content "$env:USERPROFILE\.claude\corp-ca-bundle.pem" -Encoding ascii

# 2) 이 터미널에 적용 후 재시도
$env:NODE_EXTRA_CA_CERTS = "$env:USERPROFILE\.claude\corp-ca-bundle.pem"
claude setup-token

# (선택) 모든 새 터미널에 영구 적용
setx NODE_EXTRA_CA_CERTS "$env:USERPROFILE\.claude\corp-ca-bundle.pem"
```

**처방 (macOS/Linux):** 회사에서 배포한 CA `.pem`(IT 부서 제공 또는 키체인에서 내보내기)을
`~/.claude/corp-ca-bundle.pem`에 두고 `export NODE_EXTRA_CA_CERTS=~/.claude/corp-ca-bundle.pem`.

래퍼는 `~/.claude/corp-ca-bundle.pem`이 존재하면 **자동으로** `NODE_EXTRA_CA_CERTS`를 설정하므로,
번들을 한 번 만들어 두면 예약 실행에는 추가 조치가 필요 없습니다.

## `gh`/`git push`가 간헐적으로 실패 — 502 / TLS handshake timeout

```
fatal: unable to access 'https://github.com/...': The requested URL returned error: 502
Post "https://api.github.com/graphql": net/http: TLS handshake timeout
```

**원인:** GitHub 쪽 일시 장애 또는 프록시 경유 네트워크 흔들림. 지속 장애가 아닙니다.

**처방:** 몇 초 간격 재시도로 대부분 해결됩니다. 트리아지 절차 자체가 크래시-세이프라
(close는 push 성공 후 — [how-it-works.md](how-it-works.md) 배치 push 불변식) 중간에 끊겨도
거짓 상태가 남지 않고, 다음 실행/`/session-briefing`이 미완 마감을 재개합니다.

## cron.log 한글이 깨짐 (Windows)

**원인:** Windows PowerShell 5.1이 BOM 없는 스크립트를 ANSI(CP949)로 읽어 비ASCII 리터럴이 손상되거나,
콘솔 인코딩이 UTF-8이 아님.

**처방:** 래퍼는 이미 대응되어 있습니다 — `run-triage.ps1`은 **ASCII 전용**으로 유지하고
콘솔 출력 인코딩을 UTF-8로 설정해 Claude가 출력한 한글은 보존합니다. 래퍼를 수정할 때
**비ASCII 문자를 넣지 마세요**(마커·헤더는 영문 유지).

## 예약이 아예 안 돎 (cron.log에 START 기록조차 없음)

- **Windows:** 작업은 로그온 세션에서만 실행됩니다(비밀번호 미저장 설계). 그 시각에 로그오프/절전이면
  스킵되고 소급 실행도 없습니다. `Get-ScheduledTask -TaskName 'IssueTriage-<폴더명>' | Get-ScheduledTaskInfo`로
  LastRunTime/LastTaskResult 확인.
- **macOS:** cron이 디스크 접근 권한이 없을 수 있습니다 — 시스템 설정 → 개인정보 보호 및 보안 →
  전체 디스크 접근 권한에 `cron` 추가, 또는 launchd로 전환.
- **공통:** 래퍼를 직접 실행해보면 스케줄러 문제인지 실행 문제인지 바로 갈립니다:
  `bash .claude/automation/run-triage.sh` / `powershell -File .\.claude\automation\run-triage.ps1`

## 헤드리스가 검증 명령을 못 돌림 (자동 처리율이 낮음)

**증상:** 단순해 보이는 이슈가 전부 "판단 필요"로 넘어감.

**원인:** 검증 명령이 `settings.json` allow에 없어 dontAsk에서 거부 → 검증 실패로 취급 → 안전 강등.

**처방:** [customization.md](customization.md#검증-명령-필수-설정) — `issue-triage.md` ✏️ 블록과
`settings.json` allow를 함께 맞추세요.

## 봇이 같은 이슈를 다시 건드림 / 반대로 새 요청을 무시함

- **다시 건드림:** 템플릿 코멘트 헤더 문자열을 수정했다면 멱등성 신호가 깨진 것입니다 —
  [customization.md](customization.md#코멘트-템플릿언어) 참조(§3 매칭 문자열과 함께 변경).
- **무시함:** 정상입니다 — 봇 코멘트가 이미 있는 이슈는 스킵됩니다. **새 요구사항은 이슈에
  새 코멘트로** 달면(봇 코멘트보다 뒤) 다음 실행이 재검토합니다.
