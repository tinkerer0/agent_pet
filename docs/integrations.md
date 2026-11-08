# 로컬 에이전트 연결

AgentPet은 터미널 앱과 독립적으로 동작합니다. Codex·Claude Code는 기본으로 감지하고, 그 밖의 도구는 작업 시작·종료 신호를 한 번 연결합니다. 세션이 열려 있다는 이유만으로 작업 중으로 세지는 않습니다.

아래 명령은 현재 소스에서 빌드한 앱을 기준으로 합니다. 다운로드 릴리스 v0.1.0에는 이 기능이 없습니다.

```sh
bash scripts/build.sh
dist/AgentPet.app/Contents/MacOS/AgentPet --help
```

`--hook-config`는 지금 실행한 AgentPet 바이너리의 절대경로가 들어간 연결 예시를 출력합니다. 앱을 다른 폴더로 옮기면 예시도 다시 만들어야 합니다. 다른 도구의 설정을 자동으로 수정하거나 신뢰 권한을 승인하지 않습니다. 기존 설정이 있으면 해당 hook 항목을 추가하고 기존 항목은 보존하세요.

## Grok

```sh
dist/AgentPet.app/Contents/MacOS/AgentPet --hook-config grok
```

출력 JSON을 `~/.grok/hooks/agent-pet.json`에 저장하고 다음 세션에서 연결합니다. `UserPromptSubmit`·도구 실행을 시작으로, `Stop`·오류·취소·`SessionEnd`를 종료로 받습니다. 해당 폴더의 hook 실행이 허용되어 있어야 합니다. [Grok hook 문서](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/10-hooks.md)

## Cursor

```sh
dist/AgentPet.app/Contents/MacOS/AgentPet --hook-config cursor
```

출력의 `hooks` 항목을 `~/.cursor/hooks.json`에 추가합니다. `beforeSubmitPrompt`·도구 실행·추론 시작 신호와 `stop`·`sessionEnd`를 받습니다. 실제 이벤트 발생 여부는 사용 중인 Cursor·CLI 버전에 따라 확인해야 합니다. [Cursor hook 문서](https://cursor.com/docs/hooks)

## Gemini CLI

```sh
dist/AgentPet.app/Contents/MacOS/AgentPet --hook-config gemini
```

출력의 `hooks` 항목을 `~/.gemini/settings.json`에 추가합니다. `BeforeAgent`·`BeforeTool`을 시작으로, `AfterAgent`·`SessionEnd`를 종료로 받습니다. [Gemini hook 문서](https://geminicli.com/docs/hooks/reference/)

## Cline CLI

```sh
dist/AgentPet.app/Contents/MacOS/AgentPet --hook-config cline
```

출력은 실행 스크립트입니다. Cline CLI의 hook 폴더에 이벤트 이름을 파일명으로 사용해 저장합니다(예: `~/.cline/hooks/TaskStart`). 시작 이벤트 `TaskStart`·`TaskResume`·`UserPromptSubmit`·`PreToolUse`, 종료 이벤트 `TaskComplete`·`TaskCancel`·`TaskError`·`SessionShutdown`마다 같은 스크립트를 등록하고 실행 권한을 부여합니다. 기존 파일이 있다면 덮어쓰지 말고 그 스크립트에서 AgentPet을 함께 호출하세요. 확장 프로그램의 hook 경로와 지원 이벤트는 CLI와 다를 수 있습니다. [Cline CLI hook 구현](https://github.com/cline/cline/blob/main/sdk/packages/core/src/hooks/hook-file-config.ts)

## OpenCode

```sh
dist/AgentPet.app/Contents/MacOS/AgentPet --hook-config opencode
```

출력은 JavaScript plugin입니다. `~/.config/opencode/plugins/agent-pet.js`에 저장하고 다음 세션에서 로드합니다. `session.status`의 `busy`·`retry`를 작업 중, `idle`·오류·삭제를 종료로 받습니다. plugin을 실행하는 OpenCode 프로세스의 PID도 함께 전달합니다. [OpenCode plugin 문서](https://docs.opencode.ai/docs/plugins/)

## 그 밖의 도구

공통 명령에 도구 이름·세션 ID·상태·해당 에이전트의 PID를 전달하면 됩니다. 아래 PID는 실제 에이전트 프로세스의 것으로 바꾸세요. 이벤트를 보내는 일회성 hook 프로세스의 PID를 사용하면 바로 종료되어 집계되지 않습니다.

```sh
dist/AgentPet.app/Contents/MacOS/AgentPet --signal my-agent session-123 busy --pid 12345
dist/AgentPet.app/Contents/MacOS/AgentPet --signal my-agent session-123 idle --pid 12345
```

도구 이름은 영문 소문자로 시작하고 소문자·숫자·하이픈으로 최대 32자입니다. `codex`·`claude`는 기본 감지와 중복되지 않도록 예약되어 있습니다. 같은 도구·세션 ID는 한 번만 셉니다. 세션 ID는 파일에 원문으로 저장하지 않습니다.

기본 hook 연결은 부모 프로세스에서 소유 에이전트를 찾습니다. 별도 실행기나 SDK가 hook을 대신 실행한다면 `--hook <도구> --pid <실제 소유 PID>`로 지정해야 합니다. 샌드박스가 AgentPet 실행이나 상태 폴더 쓰기를 막으면 해당 환경에서 명시적으로 허용하기 전에는 신호가 전달되지 않습니다.

## 확인과 한계

```sh
dist/AgentPet.app/Contents/MacOS/AgentPet --status
```

작업 중인 추가 도구는 JSON의 `additional`에 표시되고, 캐릭터와 메뉴에는 기존 두 도구와 합친 수가 반영됩니다. 추가 도구가 쉬거나 연결되지 않았다면 `additional`은 비어 있을 수 있습니다.

이벤트 해석·저장·합산·프로세스 종료 처리는 테스트로 확인합니다. 각 도구의 실제 로그인 세션에서 hook이 발생하는지는 설치 버전과 hook 설정에 의존합니다. 신호 연결 전부터 진행 중이던 작업, 종료 이벤트 누락, 차단된 hook, 다른 컴퓨터나 브라우저 안의 대화까지 자동으로 알아내지는 못합니다. 정상적인 장시간 작업이 사라지지 않도록 고정 만료 시간을 두지 않습니다.
