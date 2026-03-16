# nocnoc

`tryknock.app` 랜딩페이지를 기준으로 만든 네이티브 macOS 앱입니다. 제품명은 `nocnoc`입니다.

기능:

- AppleSPUHID accelerometer를 통해 MacBook chassis 탭 감지
- single / double / triple knock 패턴 인식
- 액션 실행: 음소거, 화면 잠금, 앱 실행, Shortcut 실행, shell command 실행
- Settings의 `Knock Test`에서 실시간 waveform과 센서값 확인
- threshold, grouping window, cooldown, waveform gain 조정

실행:

```bash
swift run
```

요구사항:

- Apple Silicon Mac
- macOS 15+
- `AppleSPUHIDDevice`가 노출되는 하드웨어

참고:

- 이 앱은 공개 `CoreMotion`이 아니라 비공개 `AppleSPUHIDDevice` 경로를 사용합니다.
- `Mute audio`와 일부 시스템 제어는 macOS 권한 또는 보안 정책의 영향을 받을 수 있습니다.
- `Run Shortcut`은 Shortcuts 앱에 해당 이름의 shortcut이 있어야 합니다.
