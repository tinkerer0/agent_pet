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
- `Sources/SessionSignals.swift`: 공통 세션 신호, 도구별 hook 해석, PID 수명 확인과 연결 예시 출력.
- `Sources/PetView.swift`: atlas 디코딩, 애니메이션, 마우스 통과와 드래그.
- `Sources/PetAppearance.swift`: 기본 Clawd 형태와 크기.
- `Sources/PetColors.swift`: 몸체·눈·불꽃 팔레트 변환과 색상 저장.
- `Sources/MotionSettingsPanel.swift`: 모션별 시작 세션 수와 3·5·10개 프리셋 설정.
- `Sources/AppDelegate.swift`: 창, 메뉴, 환경설정, 화면 상태.
- `Resources/`: 여섯 단계의 atlas PNG와 타이밍 JSON, 이전 캐릭터 에셋.
- `Tests/`: 로그 수명주기·잘린 기록·중복 제거·단계 안정성·에셋 렌더링·색상 변환과 저장 확인.

기본 프레임은 48×42입니다. PNG에는 프레임이 가로로 나열되며 JSON의 `durations`는 밀리초 단위입니다. 현재 앱에는 접두사가 없는 Clawd 에셋 여섯 개만 넣습니다. `codex-`, `grok-`, `together-` 에셋은 이전 디자인 자료로 보존합니다.

몸체·눈·불꽃은 원본 atlas의 해당 색만 바꿉니다. 그림자와 불꽃의 밝은 중심은 선택색에서 만들며, 검정 몸체에는 밝은 면을 추가해 입체감을 유지합니다. 매번 원본에서 변환하므로 색을 반복해서 바꿔도 누적 손실이 없습니다. 기본색은 원본과 같습니다. 투명도·노트북·연기·zzz는 그대로입니다.

기본 설정의 7–9개와 10개 이상은 같은 불꽃 팔레트를 쓰고, 크기·불티·타이핑 속도로 단계를 구분합니다. 큰 불꽃 위쪽 불씨는 `PetView.swift`의 `RushEmbers`가 원본 프레임 위에 그리며 선택한 불색을 따릅니다. 색상과 감지 대상은 독립적이며, 추가 도구는 [공통 세션 연결](docs/integrations.md)로 합계에 포함합니다.

`StageThresholds`는 집중·연기·불꽃·폭주의 시작 세션 수를 저장합니다. 각 값은 1~99이며 같거나 증가하는 순서여야 합니다. 같은 값은 더 높은 단계가 우선하고, 0 이하는 항상 휴식입니다. 잘못된 저장값은 기본값으로 복구합니다. 기준 변경 시 단계 대기를 초기화해 즉시 반영하며, 미리보기는 세션 수 대신 모션을 직접 선택합니다.

작은·보통·큰·아주 큰 크기는 각각 픽셀 2·3·4·6배이며, 보간 없이 그립니다. 시스템의 동작 줄이기와 화면 잠자기를 반영합니다.
