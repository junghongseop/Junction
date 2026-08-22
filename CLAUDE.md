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
| 주행 후 복기 (무엇을 알아야 했는지 설명) | `Services/Drive` · `Services/Debrief` |

## 현재 상태 (중요)

**`Services/NaverMaps` · `Services/SpeedLimit` · `Services/Parking` · `Services/Enforcement` 가
실제로 동작한다.** 나머지 서비스(`RoadSign`, `TollGate`)는 껍데기(stub)로,
프로토콜과 도메인 모델만 정의되어 있고 구현부는 `[]` / `nil` / `TODO` 다.
파일 헤더에 `⚠️ 아직 껍데기(stub)입니다` 주석이 붙어 있으면 미구현이라는 뜻이다.

제품 UI 는 **홈 → 검색 → 경로 미리보기 → 주행 → Debrief** 까지 이어진다.
`HomeView` 가 Map / Trip / Settings 세 탭을 가진 `TabView` 이고,
Map 탭(`Features/Home/Map`)이 현재 위치를 중심으로 지도를 띄운다. Trip 탭과
Settings 의 설정 항목은 아직 껍데기다.

Debrief(주행 후 복기)는 `Features/Debrief` 다. 자세한 구조는 아래 "Debrief" 절 참고.
`RoadSign` · `TollGate` 는 여전히 stub 이지만, Debrief 의 톨게이트 안내는 그것을
기다리지 않고 `DrivingRoute.tollGateSteps` 만으로 돌아간다.

서비스 계층 검증용 화면(`Test/`)은 **Settings 탭 > Developer 섹션**에 있다.
제품 출시 전에 그 섹션을 통째로 걷어내면 된다.

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
├── Features/     화면 단위. 앞으로 여기에 제품 UI 를 쌓는다
│   └── Home/        HomeView(TabView) + Map / Trip / Settings
├── Services/     도메인 로직. 화면을 몰라야 한다
│   ├── NaverMaps/   ✅ 구현 완료
│   ├── SpeedLimit/  ✅ 구현 완료 (번들 SQLite 기반, 오프라인)
│   ├── Location/    ✅ 현재 위치 (CoreLocation 래퍼)
│   ├── RoadSign/    ⬜ stub
│   ├── TollGate/    ⬜ stub
│   ├── Parking/     ✅ 구현 완료 (Junction 백엔드 · 공용 전송 계층도 여기 있다)
│   └── Enforcement/ ✅ 구현 완료 (Junction 백엔드)
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

**제품 화면은 네이티브 SDK**(`NMapsMap`, SPM 3.23.3)를 쓴다 →
`Features/Home/Map/NaverMapView.swift`. 현위치 추적(`positionMode`)과 야간 스타일이
필요해서 웹 대신 네이티브로 갔다. 컨트롤러(`NaverMapController`)는 `NaverMapWebController`
와 이름을 맞췄지만 아직 `focus` / `moveToCurrentLocation` / `clear` 만 구현되어 있다.
`showMarkers` / `showRoute` / `highlight` 는 경로 안내 화면을 붙일 때 채운다.

네이티브 SDK 는 **Mobile Dynamic Map** 서비스 + iOS 번들 ID 등록이 필요하다
(Web 서비스 URL 과는 별개). 키는 `DriveInGyeongbukApp.configureNaverMapsSDK()` 가
`AppConfig` 를 거쳐 `NMFAuthManager.shared().ncpKeyId` 에 넣는다.
Info.plist 의 `NMFNcpKeyId` 는 쓰지 않는다 — 키가 비었을 때 `$(...)` 가 그대로
넘어가 인증 실패 팝업만 뜨기 때문이다.

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

## 주차장 · 주정차 금지구역 백엔드

`Services/Parking` 과 `Services/Enforcement` 는 별도 백엔드를 쓴다. 앱에는 키가 필요 없다.

```
https://junction-server.onrender.com   (스펙: /docs, /openapi.json)
  GET /api/v1/parking-lots          목적지 반경 2km 주차장
  GET /api/v1/parking-restrictions  목적지 반경 2km 주정차 금지구역
  GET /health
```

전송 계층은 `Services/Parking/JunctionServerAPI.swift` 한 곳에 있고 두 서비스가 나눠 쓴다.
구조는 `NaverMapsRequestRunner` 와 같다 (`JunctionServerHTTPClient` 로 목 교체 가능).

```swift
let parking = ParkingService()
try await parking.suggestions(near: route.goal, radiusMeters: 1000)   // 거리순 · 도보 시간 포함

let enforcement = EnforcementService()
try await enforcement.zones(near: route.goal, radiusMeters: 1000)     // 도착 전 1회 (네트워크)
enforcement.warnings(at: here)                                        // 위치 갱신마다 (메모리)
```

주의할 점

- **검색 반경은 서버에서 2km 고정**이다. 쿼리로 못 바꾼다. 더 좁게 보려면 받아온 뒤 앱에서
  잘라낸다 — 두 서비스의 `radiusMeters` 인자가 그 일을 한다(2km 초과분은 무시된다).
- **경상북도 전용**이다. 도 밖 좌표는 400 → `JunctionServerError.outsideCoverage`.
- 서버가 요청마다 원본 데이터를 읽고 네이버 Geocoding/Directions 를 호출한다. 느리고
  (무료 호스팅이라 콜드 스타트 수십 초) 짧은 시간에 몰아치면 502(`upstreamFailure`)가 난다.
  타임아웃 기본값을 60초로 잡아 둔 이유다. 두 서비스 모두 결과를 캐싱한다.
- 주차장 응답 필드는 **이름 · 위도 · 경도 셋뿐**이다. 요금 · 면수 · 운영시간은 오지 않아
  `ParkingLot` 에도 없다. 위/경도는 숫자가 아니라 **문자열**로 온다.
- 금지구역의 `path` 는 실제 도로 경로 좌표열이다. 서버는 Polygon 을 만들지 않으므로
  지도에 그리려면 앱에서 폴리라인으로 그려야 한다. **좌표가 하나뿐인 구간도 있다**
  (시작점과 종료점이 같게 해석된 경우).
- 시간표의 `start`/`end` 는 하루에 구간이 여러 개면 `"08:00+11:30+18:00"` 처럼 `+` 로 이어진다.
  `00:00~00:00` 은 "그 요일엔 규칙 없음"으로 취급한다(24시간 금지가 아니다).
- **공휴일 판정은 서버만 정확하다.** 앱에는 공휴일 목록이 없어
  `RestrictionSchedule.status(at:)` 는 일요일만 공휴일로 본다. 그래서
  `EnforcementService` 는 조회 후 5분(`serverStatusLifetime`) 안에는 서버가 준
  `serverStatus` 를 그대로 쓰고, 그 뒤부터 시간표로 다시 계산한다.
- 단속 카메라 · 어린이 보호구역은 이 API 에 없다. 별도 소스가 필요하다.

## Debrief

주행이 끝나면 `DebriefService` 가 파이프라인 한 번을 돌린다. 단계는 파일 머리말에 그려 뒀다.

```
DriveRecording → (공공데이터) → 규칙 기반 감지 → 검증 콘텐츠 첨부 → LLM → 화면
```

**무엇이 AI 고 무엇이 아닌지가 이 기능의 설계 그 자체다.** 사건 판단은 전부 규칙 기반
(`Services/Debrief/Detectors`)이고, LLM 은 **감지된 사건 중 무엇을 설명할지 고르고,
`TrafficRuleRepository` 의 검증된 문장을 다시 쓰는 일만** 한다. 법규·과태료·연락처를
지어내지 못하도록 프롬프트(`DebriefPrompt`)와 응답 스키마 양쪽에서 막고, 받은 뒤에도
`GeminiDebriefLLMClient.sanitize` 와 `DebriefService` 가 한 번씩 더 거른다.

LLM 호출이 실패해도 화면은 비지 않는다. `DebriefLLMClientFactory` 가 규칙 기반
`MockDebriefLLMClient` 로 대체하고 사유를 `Debrief.dataWarnings` 에 남긴다.
개발자 화면(Settings > Developer > Debrief 시뮬레이션)에서 그 경고를 볼 수 있다.

### Gemini Interactions API

`Services/Debrief/LLM/GeminiInteractionsAPI.swift`. `POST /v1beta/interactions`,
모델은 `gemini-3.6-flash`. 예전 `:generateContent` 와 요청·응답 모양이 다르다.

`gemini-2.5-flash` 는 **쓸 수 없다.** 신규 사용자에게 막혀 있어 400 이 나고, 구글이
응답에서 직접 `gemini-3.6-flash` 를 지목한다. 쿼터는 모델별로 따로 잡히므로
한 모델이 429 로 막혀도 다른 모델은 멀쩡하다 — 디버깅할 때 헷갈리기 쉽다.

- 본문은 `candidates[].content.parts[]` 가 아니라 **`steps[].content[].text`** 에 있다.
  `steps` 에는 `type: "thought"` 스텝이 섞여 오고 **그 스텝에는 `content` 가 없다.**
  본문은 `type: "model_output"` 스텝에만 있다.
- **`generation_config.max_output_tokens` 는 생각 토큰과 출력 토큰의 합에 걸린다.**
  이 모델은 답을 내기 전 생각에만 700~1500 토큰을 쓴다. 본문 길이만 보고 한도를 잡으면
  생각이 예산을 먹고 본문이 중간에 잘린다. 잘려도 **HTTP 200 이고 `steps` 모양도 정상**
  이라 파싱 실패로만 보인다. 구분은 `status` 뿐이다 (`completed` vs `incomplete`) →
  `GeminiInteractionResponseDTO.isIncomplete` 로 걸러 `GeminiError.truncated` 를 던진다.
- 생각 강도는 **`generation_config.thinking_level`** (`low`/`medium`/`high`). 끄는 값은 없다.
  `thinking_config` · `reasoning_effort` 는 이 API 가 모르는 이름이라 400 이 난다.
- 구조화 출력은 `generationConfig.responseSchema` 가 아니라 최상위 **`response_format`**.
  `type` 은 **`text`** 여야 한다 (`json_schema` · `json_object` 는 지원 목록에 없어 400).
  `type: "text"` + `mime_type: "application/json"` + `schema` 조합에서 enum 까지 강제된다.
- 무료 티어는 **분당 요청 수 제한(20)** 이 빡빡하다. 연달아 시험하면 429 가 뜨는데
  키나 코드 문제가 아니다. `GeminiError.rateLimited` 로 구분된다.

키는 `Config.xcconfig` 의 `Gemini_API_Key` 다. 비어 있으면 규칙 기반 목으로 돌아가고
감지·화면은 그대로 동작한다.

## 참고 문서

- `Docs/NaverMaps.md` — NCP 콘솔 설정, 서비스별 구현 상태, 테스트 UI 사용법
