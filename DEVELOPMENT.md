# 빌드와 에셋

앱은 Swift와 AppKit으로 작성했으며 외부 런타임 의존성이 없습니다. 빌드에는 macOS와 Xcode Command Line Tools가 필요합니다.

```sh
bash scripts/build.sh
bash scripts/test.sh
bash scripts/test.sh dist/AgentPet.app/Contents/Resources
```

기본 빌드는 현재 Mac 아키텍처를 사용합니다. 배포용 Universal 빌드:

```sh
ARCHS="arm64 x86_64" bash scripts/build.sh
ditto -c -k --sequesterRsrc --keepParent dist/AgentPet.app dist/AgentPet-macOS-universal.zip
```

`AGENT_PET_VERSION`은 `0.1.0` 형식의 버전, `AGENT_PET_OUTPUT_APP`은 별도 앱 출력 경로를 지정합니다. 빌드는 `/Applications`에 설치하지 않습니다.

## 구조

- `Sources/AgentMonitor.swift`: 로컬 작업 수 판독과 단계 전환.
- `Sources/PetView.swift`: atlas 디코딩, 애니메이션, 마우스 통과와 드래그.
- `Sources/PetAppearance.swift`: 세 캐릭터 모드와 크기.
- `Sources/AppDelegate.swift`: 창, 메뉴, 환경설정, 화면 상태.
- `Resources/`: 세 모드 × 여섯 단계의 atlas PNG와 타이밍 JSON.
- `Tests/`: 로그 수명주기·잘린 기록·중복 제거·단계 안정성·에셋 렌더링 확인.

단독 프레임은 48×42, 함께 프레임은 96×48입니다. PNG에는 프레임이 가로로 나열되며 JSON의 `durations`는 밀리초 단위입니다. `codex-`, `together-` 접두사로 모드를 구분합니다. 접두사가 없는 에셋은 Clawd입니다.

함께 모드 atlas에는 두 타임라인의 전환 시점을 합친 프레임이 들어 있습니다. 작은·보통·큰·아주 큰 크기는 각각 픽셀 2·3·4·6배이며, 보간 없이 그립니다. 시스템의 동작 줄이기와 화면 잠자기를 반영합니다.
