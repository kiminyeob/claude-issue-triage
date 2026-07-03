#!/usr/bin/env node
/**
 * guard.js — PreToolUse 안전 가드 (방어 심층화 계층)
 *
 * settings.json 의 deny 패턴은 "명령 접두사"만 매칭하므로 플래그가 명령 뒤쪽에
 * 붙은 형태(예: `git push origin main --force`)나 `+` refspec 강제 push 를 놓친다.
 * 이 훅은 명령을 **셸처럼 토큰화**해 argv 구조 위에서 검사하므로:
 *   - 위치·순서·따옴표와 무관하게 파괴적 명령을 차단하고,
 *   - 커밋 메시지/코멘트 본문에 우연히 들어간 "rm -rf" 같은 문자열은 오탐하지 않는다.
 *
 * 입력: stdin 으로 PreToolUse 훅 JSON({ tool_name, tool_input:{ command } }).
 * 출력: 위험하면 exit 2 + stderr(차단) / 그 외 exit 0(허용).
 * 원칙: 파싱 실패는 fail-open(exit 0) — 훅은 보조 방어선이고, 1차 방어는
 *       settings.json 의 deny/allow + dontAsk 기본 거부이기 때문.
 *
 * 차단 대상(위치·플래그 순서·따옴표 무관):
 *   - git push 의 force / force-with-lease / delete / mirror / prune / `+`refspec
 *   - git push 의 origin 이외 원격/URL
 *   - git reset --hard / git clean -f / git checkout <경로 파기> / git restore
 *   - rm -rf (Bash)
 *   - PowerShell Remove-Item/ri/rd/rmdir/del/erase 의 재귀 삭제(-Recurse, /s)
 */

'use strict';

function readStdin() {
  return new Promise((resolve) => {
    let data = '';
    try {
      process.stdin.setEncoding('utf8');
    } catch (_) {
      /* stdin may be unavailable */
    }
    process.stdin.on('data', (chunk) => (data += chunk));
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', () => resolve(data));
    setTimeout(() => resolve(data), 3000); // stdin 이 안 닫히면 fail-open
  });
}

/**
 * 명령 문자열을 셸처럼 토큰화해 "단순 명령 세그먼트" 배열로 나눈다.
 * 따옴표('...', "...")는 한 토큰으로 묶고 내용은 리터럴로 취급(플래그 매칭 제외).
 * 세그먼트 구분: 따옴표 밖의 && || | ; & 연산자.
 * 반환: string[][] (세그먼트별 argv 토큰 배열).
 */
function tokenize(cmd) {
  const segments = [];
  let cur = [];
  let tok = '';
  let hasTok = false;
  let state = 0; // 0=normal, 1=single, 2=double
  const n = cmd.length;
  const pushTok = () => {
    if (hasTok) {
      cur.push(tok);
      tok = '';
      hasTok = false;
    }
  };
  const pushSeg = () => {
    pushTok();
    if (cur.length) {
      segments.push(cur);
      cur = [];
    }
  };
  for (let i = 0; i < n; i++) {
    const ch = cmd[i];
    if (state === 1) {
      if (ch === "'") state = 0;
      else {
        tok += ch;
        hasTok = true;
      }
      continue;
    }
    if (state === 2) {
      if (ch === '"') state = 0;
      else if (ch === '\\' && i + 1 < n && '"\\$`'.includes(cmd[i + 1])) {
        tok += cmd[++i];
        hasTok = true;
      } else {
        tok += ch;
        hasTok = true;
      }
      continue;
    }
    // normal
    if (ch === "'") {
      state = 1;
      hasTok = true;
      continue;
    }
    if (ch === '"') {
      state = 2;
      hasTok = true;
      continue;
    }
    if (ch === '\\' && i + 1 < n) {
      tok += cmd[++i];
      hasTok = true;
      continue;
    }
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
      pushTok();
      continue;
    }
    if (ch === '&' || ch === '|' || ch === ';') {
      pushSeg();
      if ((ch === '&' && cmd[i + 1] === '&') || (ch === '|' && cmd[i + 1] === '|')) i++;
      continue;
    }
    tok += ch;
    hasTok = true;
  }
  pushSeg();
  return segments;
}

// 선행 env 대입(FOO=bar)·래퍼(sudo/env/nice/time/command/\)를 걷어내고 실제 argv 반환
function stripPrefixes(seg) {
  let i = 0;
  while (i < seg.length) {
    const t = seg[i];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) {
      i++;
      continue;
    }
    if (['sudo', 'env', 'nice', 'command', '\\', 'time'].includes(t.toLowerCase())) {
      i++;
      continue;
    }
    break;
  }
  return seg.slice(i);
}

const isFlag = (t) => t.startsWith('-');
const shortForce = (t) => /^-[a-z]*f[a-z]*$/i.test(t); // -f, -fd, -uf, -Rf ... (대소문자 무관)
const shortRecursive = (t) => /^-[a-z]*r[a-z]*$/i.test(t); // -r, -R, -rf, -Rf ... (대소문자 무관)

function checkGit(argv, toolName) {
  // git 전역 옵션 건너뛰고 subcommand 위치 찾기
  let si = 1;
  while (si < argv.length) {
    const t = argv[si];
    if (['-C', '-c', '--namespace', '--git-dir', '--work-tree', '--exec-path'].includes(t)) {
      si += 2;
      continue;
    }
    if (t.startsWith('-')) {
      si++;
      continue;
    }
    break;
  }
  const sub = (argv[si] || '').toLowerCase();
  const rest = argv.slice(si + 1);

  if (sub === 'push') {
    const forceTok = rest.some(
      (t) =>
        /^--force$/i.test(t) ||
        /^--force-with-lease(=.*)?$/i.test(t) ||
        /^--mirror$/i.test(t) ||
        /^--delete$/i.test(t) ||
        /^--prune$/i.test(t) ||
        shortForce(t)
    );
    if (forceTok) return 'git push 의 force/delete/mirror/prune 계열은 원격 이력을 손상시킬 수 있어 차단됩니다.';
    // `+` refspec = 강제 push 약칭 (예: +main, +HEAD:main, +refs/heads/main:...)
    if (rest.some((t) => !isFlag(t) && t.startsWith('+')))
      return 'git push 의 `+` refspec(강제 push)은 차단됩니다.';
    // origin 이외 원격/URL 차단 (push 뒤 첫 위치인자 = remote; -o/--push-option 값 건너뜀)
    let remote = null;
    for (let k = 0; k < rest.length; k++) {
      const t = rest[k];
      if (t === '-o' || t === '--push-option') {
        k++;
        continue;
      }
      if (isFlag(t)) continue;
      remote = t;
      break;
    }
    if (remote !== null && remote !== 'origin')
      return 'origin 이외의 원격/URL 로의 push(' + remote + ')는 차단됩니다.';
    return null;
  }

  if (sub === 'reset') {
    if (rest.some((t) => /^--hard$/i.test(t)))
      return 'git reset --hard 는 작업 내용을 되돌릴 수 없이 파기하므로 차단됩니다.';
    return null;
  }

  if (sub === 'clean') {
    if (rest.some((t) => shortForce(t) || /^--force$/i.test(t)))
      return 'git clean -f 는 추적되지 않는 파일을 영구 삭제하므로 차단됩니다.';
    return null;
  }

  if (sub === 'checkout') {
    // 브랜치 전환은 허용하되, 작업트리 파기 형태(`--`, `.`)만 차단
    if (rest.some((t) => t === '--' || t === '.'))
      return 'git checkout 의 작업트리 파기 형태(-- / .)는 차단됩니다.';
    return null;
  }

  if (sub === 'restore') {
    return 'git restore 는 작업트리 변경을 파기할 수 있어 차단됩니다.';
  }

  return null;
}

function checkSegment(seg, toolName) {
  const argv = stripPrefixes(seg);
  if (!argv.length) return null;
  const cmd0 = argv[0].toLowerCase();

  if (cmd0 === 'git') return checkGit(argv, toolName);

  // POSIX rm -rf (Bash). PowerShell 의 rm 은 Remove-Item 별칭이므로 아래 PS 분기에서 처리.
  if (cmd0 === 'rm' && toolName !== 'PowerShell') {
    const flags = argv.slice(1).filter(isFlag);
    const recursive = flags.some((t) => shortRecursive(t) || /^--recursive$/i.test(t));
    const force = flags.some((t) => shortForce(t) || /^--force$/i.test(t));
    if (recursive && force) return 'rm -rf(재귀 강제 삭제)는 차단됩니다.';
    return null;
  }

  // PowerShell 재귀 삭제: Remove-Item 및 별칭(ri/rm/rd/rmdir/del/erase) + -Recurse 또는 /s
  if (['remove-item', 'ri', 'rm', 'rd', 'rmdir', 'del', 'erase'].includes(cmd0)) {
    const args = argv.slice(1);
    if (args.some((t) => /^-Recurse$/i.test(t)) || args.some((t) => t === '/s' || /^\/s$/i.test(t)))
      return 'PowerShell 재귀 삭제(-Recurse / /s)는 차단됩니다.';
    return null;
  }

  return null;
}

/** 위험 명령이면 사유 문자열, 아니면 null */
function assess(command, toolName) {
  if (!command || typeof command !== 'string') return null;
  const segments = tokenize(command);
  for (const seg of segments) {
    const reason = checkSegment(seg, toolName);
    if (reason) return reason;
  }
  return null;
}

// require/module 을 쓰지 않는 단일 파일 스크립트 — 대상 프로젝트의 모듈 방식(CJS/ESM)과 무관하게 동작한다.
// 진입점은 아래 IIFE 하나. (테스트는 stdin+exit code 로 구동 — module export 불필요.)
(async function main() {
  const raw = await readStdin();
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch (_) {
    process.exit(0); // 파싱 실패 → fail-open
  }
  const toolName = payload && payload.tool_name;
  if (toolName !== 'Bash' && toolName !== 'PowerShell') process.exit(0);

  const command =
    payload.tool_input && (payload.tool_input.command || payload.tool_input.script);
  const reason = assess(command, toolName);
  if (reason) {
    process.stderr.write('[guard] 차단됨: ' + reason + '\n');
    process.exit(2); // PreToolUse: exit 2 = 도구 호출 차단
  }
  process.exit(0);
})();
