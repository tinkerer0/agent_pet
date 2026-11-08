# AgentPet

**로컬 AI 에이전트의 작업 수에 맞춰 타이핑하고, 쉬고, 불타는 macOS 데스크톱 친구.**

Clawd·Cody·Grok, 그리고 Clawd와 Cody가 한 책상에서 함께 일하는 모드 중에서 고를 수 있습니다. 세 캐릭터는 같은 형태에 서로 다른 색을 입혔습니다. 작업이 없으면 눈을 감고 쉬고, 바빠질수록 연기와 불꽃이 커집니다.

| 캐릭터 | 몸색 | 불꽃 |
| --- | --- | --- |
| Clawd · Claude | 주황 | 일렉트릭 블루 |
| Cody · Codex | 하늘색 | 코랄 |
| Grok | 보라 | 라임 |

| 0개 · 휴식 | 1–2개 · 여유 | 3–4개 · 집중 |
| :---: | :---: | :---: |
| ![0개 세션: 눈을 감고 쉬는 Clawd와 Cody](docs/previews/sessions-00.gif) | ![1–2개 세션: 여유롭게 타이핑](docs/previews/sessions-01-02.gif) | ![3–4개 세션: 집중해서 타이핑](docs/previews/sessions-03-04.gif) |
| **5–6개 · 연기** | **7–9개 · 불꽃** | **10개 이상 · 더 큰 불꽃** |
| ![5–6개 세션: 빠른 타이핑과 연기](docs/previews/sessions-05-06.gif) | ![7–9개 세션: 일렉트릭 블루와 코랄 불꽃](docs/previews/sessions-07-09.gif) | ![10개 이상 세션: 같은 색으로 더 커진 불꽃과 불티](docs/previews/sessions-10-plus.gif) |

함께 모드의 실제 애니메이션입니다. Clawd·Cody·Grok을 각각 표시할 수도 있습니다.

![보라색 Grok과 라임 불꽃](docs/previews/grok.gif)

## 설치

[최신 버전 다운로드](https://github.com/tinkerer0/agent_pet/releases/latest) → ZIP을 풀고 `AgentPet.app`을 실행하세요.

현재 릴리스 v0.1.0에는 이전 캐릭터가 들어 있습니다. 위의 새 색상과 Grok은 아래 소스 빌드로 사용할 수 있습니다.

macOS 13 이상용으로 빌드합니다. Apple Silicon에서 실행을 확인했으며, Intel은 빌드 검증만 했습니다. 배포 앱은 ad-hoc 서명이며 Apple 공증을 받지 않았습니다. macOS가 실행을 차단하면 직접 빌드해서 사용할 수 있습니다.

Xcode Command Line Tools가 있다면 저장소만으로 빌드할 수 있습니다. 캐릭터 에셋도 포함되어 있습니다.

```sh
git clone https://github.com/tinkerer0/agent_pet.git
cd agent_pet
bash scripts/build.sh
open dist/AgentPet.app
```

## 사용법

- **드래그:** 위치 이동. 위치와 크기, 선택한 캐릭터는 다음 실행에도 유지됩니다.
- **우클릭 또는 메뉴 막대:** 캐릭터·크기 변경, 단계 미리보기, 자동 감지, 종료.
- **함께 모드:** Clawd와 Cody가 한 책상에서 서로 다른 박자로 타이핑합니다.
- **투명한 여백:** 아래에 있는 앱을 그대로 클릭할 수 있습니다.

| 작업 중인 세션 | 모습 |
| --- | --- |
| 0 | 손을 내리고 눈을 감은 채 휴식 · 떠오르는 zzz |
| 1–2 | 여유롭게 타이핑 |
| 3–4 | 집중해서 타이핑 |
| 5–6 | 빠른 타이핑 · 연기 |
| 7–9 | Clawd 일렉트릭 블루 · Cody 코랄 · Grok 라임 불꽃 |
| 10 이상 | 같은 불꽃 색 · 더 큰 불꽃과 불티 · 더 빠른 타이핑 |

어떤 캐릭터를 선택해도 감지한 에이전트의 **전체 작업 수**에 반응합니다. 2초마다 확인하고, 낮아진 단계는 4초간 유지될 때 전환합니다. ‘자동 · 실제 작업 수’를 선택하면 미리보기를 끝냅니다.

## 지원하는 세션

| 도구 | 연결 방식 |
| --- | --- |
| Codex · Claude Code | 기본 자동 감지 |
| Grok · Cursor · Cline · Gemini CLI | 각 도구의 로컬 hook 연결 |
| OpenCode | 로컬 plugin 연결 |
| 그 밖의 도구 | 공통 `--signal` 명령으로 시작·종료 알림 |

특정 터미널 앱이나 세션 관리 앱은 필요하지 않습니다. 추가 도구는 최초 연결 후부터 셉니다. 모든 프로그램의 작업 상태를 설정 없이 알아내는 방식은 아니며, 브라우저 채팅·다른 컴퓨터의 세션은 포함하지 않습니다. [도구 연결 방법과 범위](docs/integrations.md)

## 감지와 개인정보

Codex의 열려 있는 로컬 세션 로그와 Claude Code의 로컬 상태 파일을 읽습니다. 추가 도구는 연결한 hook·plugin의 작업 이벤트를 받습니다. API 키와 외부 네트워크 연결이 필요하지 않으며, 대화 내용을 별도로 저장하거나 전송하지 않습니다.

감지는 각 도구의 기록·이벤트 형식에 의존합니다. 형식이 바뀌거나 종료 신호가 누락되는 환경에서는 수가 다를 수 있습니다. [감지 방식과 저장 정보](PRIVACY.md)

```sh
bash scripts/test.sh
dist/AgentPet.app/Contents/MacOS/AgentPet --status
```

[빌드·에셋 구조](DEVELOPMENT.md)

## Feedback

제가 이런 분야를 접한 지 얼마 안 돼서 부족한 점이 많습니다. 고칠 점이나 알려주실 내용이 있다면 issue나 PR로 남겨주시면 너무 감사하겠습니다.

## License

코드는 [MIT](LICENSE)입니다. Clawd와 색상 변형 캐릭터의 디자인은 MIT에 포함되지 않습니다. 이 앱은 Anthropic·OpenAI·xAI와 관계없는 개인 프로젝트입니다. [캐릭터 고지](THIRD_PARTY_NOTICES.md)
