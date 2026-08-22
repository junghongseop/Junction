# NaverMaps 서비스 연동 메모

## 1. 로컬 설정 (API 키)

키는 저장소에 커밋하지 않습니다. `Config.xcconfig` 는 `.gitignore` 대상입니다.

```bash
cp DriveInGyeongbuk/Config/Config.xcconfig.sample DriveInGyeongbuk/Config/Config.xcconfig
```

복사한 파일에 NAVER Cloud Platform 콘솔에서 발급받은 값을 채웁니다.

```
Naver_Map_Client_ID     = <Client ID (API Key ID)>
Naver_Map_Client_Secret = <Client Secret (API Key)>
```

NCP 콘솔 > Services > Application Services > Maps 에서 아래 세 가지를 모두 켜 두세요.

| 사용하는 곳 | 필요한 서비스 |
| --- | --- |
| 지도 표시 (테스트 UI) | Web Dynamic Map |
| `NaverGeocodingService` | Geocoding / Reverse Geocoding |
| `NaverDirectionsService` | Directions 5 |

### Web 서비스 URL 등록

Web Dynamic Map 은 요청 도메인을 콘솔에 등록된 값과 대조합니다.
테스트 UI 는 `AppConfig.naverMapWebServiceURL`(기본값 `https://localhost`)을
WKWebView 문서의 base URL 로 씁니다. 같은 값을 콘솔의 **Web 서비스 URL** 에
등록해야 지도가 뜹니다. 등록이 안 되어 있으면 화면에 인증 실패 메시지가 표시됩니다.

키가 비어 있거나 인증이 실패하면 테스트 화면 상단에 그대로 사유가 노출되니,
지도가 회색으로만 보이면 그 문구를 먼저 확인하세요.

## 2. 구현된 것 / 아직 껍데기인 것

```
Services/
├── NaverMaps/          ✅ 구현 완료
│   ├── NaverMapDTO.swift            설정 · 에러 · 전송 계층 · 응답 DTO · 도메인 모델
│   ├── NaverGeocodingService.swift  주소 ↔ 좌표
│   └── NaverDirectionsService.swift 자동차 경로 탐색
├── SpeedLimit/         ✅ 구현 완료 (번들 SQLite 기반 제한속도 안내 · 오프라인)
│   ├── KoreaCoordinateConverter.swift  WGS84 ↔ EPSG:5179 변환
│   ├── SpeedLimitLink.swift            도메인 모델 (링크 · 매칭 · 도로등급)
│   ├── SpeedLimitGeometry.swift        GSL1 형상 파서 · 폴리라인 계산 · 공간 인덱스
│   ├── SpeedLimitDataSource.swift      번들 SQLite 조회 (R-tree)
│   └── SpeedLimitService.swift         경로 구간 분할 · 초과 경고 / 감속 예고
├── RoadSign/           ⬜ 껍데기 (한국어 표지판 인식 · 외국어 해설)
├── TollGate/           ⬜ 껍데기 (톨게이트 차로 안내)
├── Parking/            ⬜ 껍데기 (도착지 인근 주차장)
└── Enforcement/        ⬜ 껍데기 (주정차 단속 구간)
```

`NaverDirectionsService` 가 만든 `DrivingRoute` 가 나머지 서비스의 공통 입력입니다.

| 소비자 | 쓰는 값 |
| --- | --- |
| `SpeedLimitService` | `route.path` (경로 폴리라인 — 표준노드링크에 좌표로 스냅) |
| `RoadSignExplanationService` | `route.steps[].instructions` (한국어 안내 원문) |
| `TollGateService` | `route.tollGateSteps` |
| `ParkingService` / `EnforcementService` | `route.goal` |

## 3. 알아 둘 점

- 네이버는 좌표를 항상 **경도,위도** 순서로 주고받습니다. 문자열 변환은
  `NaverCoordinate.apiQueryValue` 로만 하세요.
- Directions 5 는 소요 시간을 **밀리초**로 줍니다. `DrivingRoute.duration` 은 초로 변환해 둡니다.
- `RouteSection.currentSpeed` 는 **현재 통행 속도**이지 제한속도가 아닙니다.
  제한속도는 `Services/SpeedLimit` 이 번들 데이터셋에서 따로 가져옵니다.
- `NaverCoordinate` / `NaverCoordinateBounds` 는 `nonisolated` 입니다. 제한속도 매칭처럼
  백그라운드에서 대량으로 다뤄야 해서 MainActor 격리에서 빼 두었습니다.
- 안내 코드(`RouteStep.rawType`)는 공개 문서 개정이 잦아 값만으로 단정하지 않고,
  `RouteGuideKind.classify(instructions:)` 가 한국어 안내 문구로 분류합니다.
  원본 코드는 `rawType` 에 그대로 남아 있습니다.
- Directions 5 는 HTTP 200 이어도 `code != 0` 이면 실패입니다. 서비스에서 처리하고 있습니다.
- 호스트/인증 헤더 이름은 `NaverMapsConfiguration` 에서 바꿀 수 있습니다.
  구형 키(`naveropenapi.apigw.ntruss.com`)를 쓰는 계정이면 이 값만 조정하면 됩니다.

## 4. 테스트 UI

`DriveInGyeongbuk/Test/` 에 있습니다. 앱을 실행하고 홈 화면의
**NaverMaps 서비스 테스트** 버튼을 누르면 열립니다.

- 출발지/도착지 주소 검색 → 좌표 · 영문 주소 확인
- 지도 탭 → 역지오코딩 결과 확인
- 탐색 옵션을 골라 경로 탐색 → 폴리라인, 거리/시간/통행료 요약
- 턴바이턴 안내 목록(원본 `type` 코드와 분류 결과 포함), 행을 누르면 지도 이동
- 도로 구간 목록(도로명 · 현재 속도 · 혼잡도)

홈 화면의 **SpeedLimit 서비스 테스트** 버튼은 제한속도 쪽 검증 화면입니다.

- 좌표(또는 지도 탭) → 주변 링크 목록 · 가장 가까운 도로와 제한속도
  → **번들 DB 만 쓰므로 API 키 없이도 확인됩니다**
- 경로 탐색 → 제한속도가 같은 구간으로 쪼갠 목록 (REST 키 필요)
- 진행률·속도 슬라이더로 주행 시뮬레이션 → 초과 경고 / 감속 예고 확인

제품 UI 가 아니라 서비스 계층 검증용이라 디자인은 최소한만 했습니다.

## 5. 지도 렌더링 방식에 대해

테스트 UI 의 지도는 **Web Dynamic Map(JavaScript API v3)** 을 `WKWebView` 로 감싼
`NaverMapWebView` 입니다. 외부 SDK 의존성이 없어 클론 직후 바로 빌드·실행됩니다.

제품 화면에서 네이티브 SDK(`NMapsMap`)로 바꾸고 싶다면 SPM 으로
`https://github.com/navermaps/SPM-NMapsMap` 을 추가하고,
`NaverMapWebController` 와 같은 인터페이스(`focus` / `showMarkers` / `showRoute` /
`highlight` / `clear`)를 갖는 구현으로 교체하면 나머지 코드는 그대로 둘 수 있습니다.
