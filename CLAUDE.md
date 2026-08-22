# DriveInGyeongbuk

경상북도를 주행하는 **외국인 운전자**를 위한 iOS 내비게이션 보조 앱.
단순 길안내가 아니라, "한국 도로에서 외국인이 당황하는 지점"을 미리 풀어 주는 것이 목적이다.

핵심 기능 (목표):

| 기능 | 담당 서비스 |
| --- | --- |
| 경로 안내 (주행 중 현재 도로 추적) | `Services/NaverMaps` |
| 제한속도 안내 · 초과 경고 | `Services/SpeedLimit` |
| 한국어 표지판 / 안내 문구를 외국어로 해설 | `Services/RoadSign` |
| 톨게이트에서 어느 차로로 붙어야 하는지 | `Services/TollGate` |
| 도착지 인근 주차장 안내 | `Services/Parking` |
| 도착지 인근 주정차 단속 구간 경고 | `Services/Enforcement` |

## 현재 상태 (중요)

**`Services/NaverMaps` 와 `Services/SpeedLimit` 이 실제로 동작한다.** 나머지 서비스는
전부 껍데기(stub)로, 프로토콜과 도메인 모델만 정의되어 있고 구현부는 `[]` / `nil` / `TODO` 다.
파일 헤더에 `⚠️ 아직 껍데기(stub)입니다` 주석이 붙어 있으면 미구현이라는 뜻이다.

제품 UI도 아직 없다. `HomeView` 는 서비스 계층 검증용 테스트 화면(`Test/`)으로 가는
버튼만 갖고 있다.

## 빌드 · 실행

```bash
# API 키 설정 (최초 1회, Config.xcconfig 는 .gitignore 대상)
cp DriveInGyeongbuk/Config/Config.xcconfig.sample DriveInGyeongbuk/Config/Config.xcconfig
# 복사한 파일에 NCP 콘솔의 Client ID / Client Secret 을 채운다

xcodebuild -project DriveInGyeongbuk.xcodeproj -scheme DriveInGyeongbuk \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- iOS 배포 타깃 **26.2**, `TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad)
- 테스트 타깃 없음. 검증은 `Test/` 의 수동 확인 화면으로 한다.
- 키가 비어 있어도 빌드·실행은 되고, 테스트 화면 상단에 사유가 문구로 노출된다.

## 아키텍처

MVVM. 레이어는 아래 3단이다.

```
View (SwiftUI)  →  ViewModel (ObservableObject)  →  Service (protocol + struct/class)
```

```
DriveInGyeongbuk/
├── App/          @main 진입점
├── Config/       AppConfig(키 주입) · Config.xcconfig(gitignore)
├── Features/     화면 단위. 현재 Home 뿐 — 앞으로 여기에 제품 UI 를 쌓는다
├── Services/     도메인 로직. 화면을 몰라야 한다
│   ├── NaverMaps/   ✅ 구현 완료
│   ├── SpeedLimit/  ✅ 구현 완료 (번들 SQLite 기반, 오프라인)
│   ├── RoadSign/    ⬜ stub
│   ├── TollGate/    ⬜ stub
│   ├── Parking/     ⬜ stub
│   └── Enforcement/ ⬜ stub
├── Resources/    Assets.xcassets
└── Test/         [테스트 전용] 서비스 계층 검증 화면. 제품 코드가 아니다
```

### 레이어 규칙

- **Service 는 SwiftUI 를 import 하지 않는다.** 순수 `Foundation` + `CoreLocation`.
- **ViewModel 은 `final class ... : ObservableObject`**, 입력은 `@Published`,
  출력은 `@Published private(set)`. `NaverMapsTestViewModel` 이 레퍼런스 구현이다.
- **View 는 상태를 갖지 않는다.** 화면 로컬 토글(`@State private var isShowing…`) 정도만 허용.

### DI 컨벤션

모든 서비스는 프로토콜 + 기본값 이니셜라이저 조합으로 주입한다. 테스트/목 교체가 목적이다.

```swift
protocol NaverGeocodingServicing { ... }

final class SomeViewModel: ObservableObject {
    init(geocodingService: NaverGeocodingServicing = NaverGeocodingService()) { ... }
}
```

네트워크는 `NaverMapsHTTPClient` 프로토콜로 한 겹 더 추상화되어 있어
`URLSession` 없이도 서비스를 테스트할 수 있다.

### 서비스 간 데이터 흐름

`NaverDirectionsService` 가 만드는 **`DrivingRoute` 가 나머지 서비스 전부의 공통 입력**이다.
새 안내 기능을 붙일 때는 여기서 시작하면 된다.

| 소비자 | 쓰는 값 |
| --- | --- |
| `SpeedLimitService` | `route.path` (경로 폴리라인 — 표준노드링크에 좌표로 스냅한다) |
| `RoadSignExplanationService` | `route.steps[].instructions` (한국어 안내 원문) |
| `TollGateService` | `route.tollGateSteps` (`kind == .tollGate` 인 스텝) |
| `ParkingService` / `EnforcementService` | `route.goal` |

`DrivingRoute` 에는 주행 중 매칭용 헬퍼가 이미 있다:
`nearestPathIndex(to:)`, `nextStep(from:)`, `section(at:)`.

## 반드시 지켜야 할 것

### 좌표

네이버 API 는 좌표를 **항상 `경도,위도`(x,y) 순서**로 주고받는다. 실수하기 딱 좋은 지점이라
변환 경로를 하나로 묶어 두었다.

- 문자열 변환은 **`NaverCoordinate.apiQueryValue` 로만** 한다.
- 응답의 `[Double]` 배열은 `NaverCoordinate(xyPair:)` 로 만든다.
- 직접 `"\(lat),\(lng)"` 를 조립하지 말 것.

### 동시성

빌드 설정이 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` 다.
즉 **어노테이션 없는 타입은 기본적으로 `@MainActor` 로 격리된다.** ViewModel 에 `@MainActor` 를
따로 안 붙여도 되는 이유가 이것이다. 백그라운드로 빼야 하는 무거운 작업(대용량 SQLite 조회,
OCR 등)은 `nonisolated` 나 별도 actor 로 명시적으로 분리해야 한다.

### 비밀 키

키는 **절대 커밋하지 않는다.** 주입 경로:

```
Config/Config.xcconfig (gitignore)  →  Info.plist ($(변수))  →  AppConfig  →  NaverMapsConfiguration
```

`AppConfig.infoValue` 는 값이 비었거나 `"$(...)"` 가 그대로 남은 경우를 걸러 낸다.
새 키가 필요하면 이 네 곳을 모두 손봐야 한다(sample 파일 포함).

### 에러 처리

- 서비스는 `NaverMapsError` (또는 도메인 에러)를 던지고, `LocalizedError` 로 한국어 사유를 준다.
- ViewModel 이 `do/catch` 로 받아 `errorMessage` 에 담는다. `run(status:_:)` 헬퍼 패턴 참고.
- **Directions 5 는 HTTP 200 이어도 `code != 0` 이면 실패**, Geocoding 은 `status != "OK"` 면 실패.
  상태 코드만 보고 성공으로 단정하지 말 것.

### 주석 · 문서 언어

코드 주석과 사용자 노출 문구는 **한국어**로 쓴다. 기존 파일 스타일을 그대로 따를 것
(파일 헤더에 목적 + 데이터 출처 + TODO 를 적는 형식).

## 알아 둘 함정

- `RouteSection.currentSpeed` 는 **현재 통행 속도**지 제한속도가 아니다.
  제한속도는 `Services/SpeedLimit` 이 번들 데이터셋에서 따로 가져온다.
- Directions 5 는 소요 시간을 **밀리초**로 준다. 앱 내부(`DrivingRoute.duration`,
  `RouteStep.duration`)는 **초**로 통일되어 있다.
- 안내 코드 `RouteStep.rawType` 은 공개 문서 개정이 잦아 값만으로 단정하지 않는다.
  분류는 `RouteGuideKind.classify(instructions:)` 가 한국어 문구 키워드로 한다.
  원본 코드는 `rawType` 에 보존된다.
- 경유지는 최대 5개 (`NaverDirectionsService.maxWaypointCount`).
- 인증 헤더 이름/호스트는 `NaverMapsConfiguration` 에서 바꿀 수 있다.
  구형 키(`naveropenapi.apigw.ntruss.com`) 계정이면 이 값만 조정하면 된다.

## 지도 렌더링

현재 테스트 화면의 지도는 **Web Dynamic Map(JS API v3)** 을 `WKWebView` 로 감싼
`Test/NaverMapWebView.swift` 다. NCP 콘솔의 **Web 서비스 URL** 에
`AppConfig.naverMapWebServiceURL`(기본 `https://localhost`)과 같은 값을 등록해야 지도가 뜬다.

네이티브 SDK(`NMapsMap`, SPM 3.23.3)는 이미 프로젝트에 추가되어 있다. 제품 화면에서
네이티브로 갈아탈 때는 `NaverMapWebController` 와 **같은 인터페이스**
(`focus` / `showMarkers` / `showRoute` / `highlight` / `clear`)를 갖는 구현으로 교체하면
나머지 코드는 그대로 둘 수 있다.

## 제한속도 데이터셋

`DriveInGyeongbuk/gyeongbuk_speed_limits.sqlite` (34MB, 커밋됨)에 경상북도 전역
표준노드링크 기반 제한속도 데이터가 들어 있다. `SQLiteSpeedLimitDataSource` 가 읽는다.
파일이 `DriveInGyeongbuk/` 폴더 안에 있어 동기화 그룹이 알아서 번들에 넣어 준다(별도 설정 불필요).

- `links` 테이블: 167,139 링크 (`link_id`, `speed_kph`, `road_name`, `road_rank`, `f_node`, `t_node`, `geometry`)
- `link_index`: R-tree 공간 인덱스 (bbox 검색용). 좌표 조회는 항상 여기를 먼저 태운다.
- 좌표계는 **EPSG:5179** (원본 EPSG:5186에서 변환). WGS84 가 아니므로 `NaverCoordinate` 와
  매칭하려면 좌표 변환이 필요하다 → `KoreaCoordinateConverter` 가 담당한다.
- `geometry` 는 `GSL1` 커스텀 바이너리 포맷 — 상세 스펙은 `metadata` 테이블의
  `geometry_format` 키에 문자열로 기록되어 있다. 파서는 `GSL1GeometryDecoder`.
- 원본 shapefile 은 `[2026-08-12]NODELINKDATA/` (gitignore 대상, 로컬에만 존재).

### 제한속도 서비스 쓰는 법

```swift
let source = try SQLiteSpeedLimitDataSource()       // 번들 DB 를 연다
let service = SpeedLimitService(dataSource: source)

try await service.prepare(for: route)               // 내비 시작 시 1회 (경로 전체를 구간으로 쪼갠다)
service.currentLimitKPH(at: here)                   // 주행 중: 현재 제한속도
service.alert(at: here, speedKPH: 82)               // 주행 중: 초과 경고 / 감속 예고
```

`prepare` 이후 조회는 전부 메모리 계산이라 위치 갱신마다 불러도 된다(호출당 ~0.001ms).
경로 없이 달릴 때는 `prepare(around:radiusMeters:)` 로 주변만 올려 두고,
`needsRefresh(at:)` 가 true 가 되면 다시 부른다.

주의할 점

- **경상북도 전용 데이터셋**이다. 도 밖에서는 아무것도 못 찾는다.
  미리 거르려면 `KoreaCoordinateConverter.isInsideDataset(_:)`.
- 표준노드링크는 이면도로에 10~20km/h 를 넣어 두는 경우가 많다. 표지판 값이 아니라
  초과 경고를 띄우면 오탐이므로 `isReliableLimit`(30km/h 미만 제외)로 걸러 쓴다.
- 이 데이터셋에는 **단속 카메라 · 보호구역 · 구간단속이 없다.** 별도 소스가 필요하다.
- 시청·관광지 같은 건물 좌표는 도로에서 70~100m 떨어져 있어 매칭되지 않는 게 정상이다.
  (매칭 허용 거리 기본값 `matchToleranceMeters = 35`)

## 참고 문서

- `Docs/NaverMaps.md` — NCP 콘솔 설정, 서비스별 구현 상태, 테스트 UI 사용법
