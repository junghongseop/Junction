//
//  EnforcementAPIClient.swift
//  DriveInGyeongbuk
//
//  주정차 금지구역 원천 데이터 클라이언트.
//
//  데이터 출처
//    GET https://junction-server.onrender.com/api/v1/parking-restrictions?latitude=&longitude=
//    → 목적지 반경 2km 안에서 현재 유효한 주정차 금지 **도로 구간**을 준다.
//
//  서버가 하는 일 (원본 공공데이터 → 응답)
//    1. 목적지를 역지오코딩해 경상북도 시군구를 확인
//    2. 시행일·해제일 기준으로 현재 유효한 레코드만 남김
//    3. 상세위치가 "A ~ B" 로 나뉘는 구간(RANGE) 유형만 처리 (POINT/AMBIGUOUS 는 제외)
//    4. 시작점·종료점을 지오코딩하고 Directions 5 로 실제 도로 경로를 조회
//    5. 목적지에서 그 경로까지의 최단거리가 2km 이하인 것만 반환
//
//  ⚠️ 서버는 Polygon 을 만들지 않는다. 지도에 색칠하려면 `path` 로 앱에서 그려야 한다.
//  ⚠️ 시작점과 종료점이 같은 좌표로 해석된 구역은 `path` 에 점이 **하나만** 들어 있다.
//

import Foundation
import CoreLocation

// MARK: - 주정차 금지구역

/// 주정차 금지 도로 구간 한 곳.
nonisolated struct EnforcementZone: Identifiable, Hashable {

    /// 도로명 + 상세위치 + 시작 좌표를 합친 안정적인 식별자.
    var id: String {
        "\(roadName)|\(detailLocation)|\(path.first?.apiQueryValue ?? "-")"
    }

    /// 원본 데이터의 도로명 (예: "안기1길").
    var roadName: String
    /// 원본 데이터의 상세위치 (예: "현대주유소 옆 ~ 대원아파트 입구").
    var detailLocation: String

    /// 금지 유형. 앱 분기용.
    var kind: Kind
    /// 표준 유형 코드. 01=절대, 02=탄력, 03=혼용.
    var typeCode: String?
    /// 화면에 표시할 한글 유형명 (서버가 준 문구 그대로).
    var koreanTypeName: String
    /// 공공데이터 표준의 유형 설명 (서버가 준 문구 그대로).
    var typeDescription: String
    /// 지정 방향 구분 코드. 의미는 지자체마다 달라 원본을 그대로 보존한다.
    var directionCode: String?

    /// 서버가 조회 시점 기준으로 계산해 준 상태.
    ///
    /// 공휴일 판정이 들어가 있어 가장 정확하다. 다만 조회 시점의 값이므로
    /// 시간이 흐른 뒤에는 `schedule.status(at:)` 로 다시 계산해 써야 한다.
    var serverStatus: RestrictionStatus

    /// 목적지에서 이 구간까지의 최단거리(m). 서버가 계산한 값.
    var distanceFromDestinationMeters: Double

    /// 실제 도로 경로 좌표열. 순서대로 이으면 도로 기준선이 된다.
    /// 점이 하나뿐일 수도 있다.
    var path: [NaverCoordinate]

    /// 요일별 금지 / 일시 허용 시간표.
    var schedule: RestrictionSchedule

    /// 구간 대표 좌표. 경로의 가운데 점을 쓴다.
    var coordinate: NaverCoordinate {
        guard !path.isEmpty else { return NaverCoordinate(latitude: 0, longitude: 0) }
        return path[path.count / 2]
    }

    /// 화면에 보여줄 이름.
    var displayName: String {
        detailLocation.isEmpty ? roadName : "\(roadName) (\(detailLocation))"
    }

    /// 금지 유형.
    enum Kind: String, Hashable {
        /// 절대 금지 — 시간과 무관하게 늘 금지.
        case absolute
        /// 탄력 금지 — 시간대·요일별로 허용 여부가 달라진다.
        case flexible
        /// 혼용 — 절대와 탄력이 섞여 있다.
        case mixed
        case unknown

        /// 서버의 영문 유형명(`ABSOLUTE` 등)에서 만든다.
        init(apiName: String) {
            switch apiName.uppercased() {
            case "ABSOLUTE": self = .absolute
            case "FLEXIBLE": self = .flexible
            case "MIXED":    self = .mixed
            default:         self = .unknown
            }
        }

        var koreanName: String {
            switch self {
            case .absolute: return "절대 금지"
            case .flexible: return "탄력 금지"
            case .mixed:    return "혼용"
            case .unknown:  return "유형 미상"
            }
        }

        var englishName: String {
            switch self {
            case .absolute: return "Always prohibited"
            case .flexible: return "Time-based"
            case .mixed:    return "Mixed"
            case .unknown:  return "Unknown"
            }
        }
    }

    // MARK: 거리 계산

    /// 주어진 좌표에서 이 구간(폴리라인)까지의 최단거리(m).
    ///
    /// 구간은 길이가 수백 m 수준이라 위경도를 기준점 주변의 평면으로 근사해도
    /// 오차가 무시할 만하다. (등거리 원통 근사)
    func distance(from coordinate: NaverCoordinate) -> CLLocationDistance {
        guard let first = path.first else { return .greatestFiniteMagnitude }
        guard path.count > 1 else { return first.distance(to: coordinate) }

        let metersPerDegreeLatitude = 111_132.0
        let metersPerDegreeLongitude = 111_320.0 * cos(coordinate.latitude * .pi / 180)

        // 기준 좌표를 원점으로 하는 평면 좌표(m).
        func project(_ point: NaverCoordinate) -> (x: Double, y: Double) {
            ((point.longitude - coordinate.longitude) * metersPerDegreeLongitude,
             (point.latitude - coordinate.latitude) * metersPerDegreeLatitude)
        }

        var best = Double.greatestFiniteMagnitude
        var previous = project(path[0])

        for index in 1..<path.count {
            let current = project(path[index])
            best = min(best, Self.distanceFromOrigin(toSegment: previous, current))
            previous = current
        }
        return best
    }

    /// 원점에서 선분 `a-b` 까지의 거리.
    private static func distanceFromOrigin(toSegment a: (x: Double, y: Double),
                                           _ b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else { return (a.x * a.x + a.y * a.y).squareRoot() }

        // 원점을 선분에 사영한 위치(0…1 로 자른다).
        let t = min(1, max(0, -(a.x * dx + a.y * dy) / lengthSquared))
        let px = a.x + t * dx
        let py = a.y + t * dy
        return (px * px + py * py).squareRoot()
    }
}

// MARK: - 제한 상태

/// 조회 시점의 주정차 제한 상태.
nonisolated enum RestrictionStatus: String, Hashable {
    /// 지금 주정차 금지.
    case restricted = "RESTRICTED"
    /// 금지 시간대이지만 지금은 일시 허용.
    case temporarilyAllowed = "TEMPORARILY_ALLOWED"
    /// 지금은 금지 시간대가 아님.
    case inactive = "INACTIVE"

    init(apiValue: String) {
        self = RestrictionStatus(rawValue: apiValue.uppercased()) ?? .inactive
    }

    /// 지금 세우면 과태료인지.
    var prohibitsParkingNow: Bool { self == .restricted }

    var koreanName: String {
        switch self {
        case .restricted:         return "주정차 금지"
        case .temporarilyAllowed: return "일시 허용"
        case .inactive:           return "제한 없음"
        }
    }

    var englishName: String {
        switch self {
        case .restricted:         return "No parking"
        case .temporarilyAllowed: return "Temporarily allowed"
        case .inactive:           return "No restriction"
        }
    }
}

// MARK: - 시간표

/// 하루 안의 시간 구간. 자정을 넘어가는 구간도 표현할 수 있다.
nonisolated struct TimeWindow: Hashable {

    /// 자정부터의 분 (0...1440).
    var startMinutes: Int
    var endMinutes: Int

    /// `"08:00"` 형식 두 개로 만든다. 형식이 어긋나면 nil.
    init?(start: String, end: String) {
        guard let startMinutes = Self.minutes(from: start),
              let endMinutes = Self.minutes(from: end) else { return nil }
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    /// 시작과 끝이 같으면 "규칙 없음"으로 본다.
    ///
    /// 원본 데이터에는 규칙이 없는 요일에 `00:00~00:00` 이 들어 있다.
    /// 이걸 24시간 금지로 읽으면 없는 단속을 경고하게 되므로 빈 구간으로 취급한다.
    var isEmpty: Bool { startMinutes == endMinutes }

    func contains(minutes: Int) -> Bool {
        guard !isEmpty else { return false }
        if endMinutes > startMinutes {
            return minutes >= startMinutes && minutes < endMinutes
        }
        // 22:00 ~ 06:00 처럼 자정을 넘는 구간.
        return minutes >= startMinutes || minutes < endMinutes
    }

    var description: String {
        "\(Self.text(from: startMinutes))~\(Self.text(from: endMinutes))"
    }

    private static func minutes(from text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0...59).contains(minute) else { return nil }
        return min(hour * 60 + minute, 24 * 60)
    }

    private static func text(from minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// 하루치 규칙.
nonisolated struct DayRestriction: Hashable {
    /// 주정차 금지 시간대.
    var prohibited: [TimeWindow]
    /// 금지 시간 안에서 예외적으로 주정차가 허용되는 시간대.
    var temporarilyAllowed: [TimeWindow]

    static let none = DayRestriction(prohibited: [], temporarilyAllowed: [])

    var isEmpty: Bool { prohibited.allSatisfy(\.isEmpty) }

    func status(atMinutes minutes: Int) -> RestrictionStatus {
        guard prohibited.contains(where: { $0.contains(minutes: minutes) }) else { return .inactive }
        if temporarilyAllowed.contains(where: { $0.contains(minutes: minutes) }) { return .temporarilyAllowed }
        return .restricted
    }

    /// 화면에 보여줄 금지 시간 문구. 규칙이 없으면 nil.
    var prohibitedDescription: String? {
        let windows = prohibited.filter { !$0.isEmpty }
        guard !windows.isEmpty else { return nil }
        return windows.map(\.description).joined(separator: ", ")
    }
}

/// 요일별 시간표.
nonisolated struct RestrictionSchedule: Hashable {

    /// 월~금.
    var weekday: DayRestriction
    var saturday: DayRestriction
    /// 일요일과 대한민국 공휴일.
    var holiday: DayRestriction
    /// 명절 연휴에 주정차를 허용하는지 (원본 데이터 값).
    var holidaySeasonAllowed: Bool

    /// 한국 시간 기준 달력.
    static let koreaCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        calendar.locale = Locale(identifier: "ko_KR")
        return calendar
    }()

    /// 주어진 시각의 제한 상태를 앱에서 직접 계산한다.
    ///
    /// ⚠️ 대한민국 공휴일 목록을 앱이 갖고 있지 않아 **일요일만** 공휴일로 본다.
    ///    설·추석 같은 공휴일에는 실제보다 엄하게(금지로) 판정될 수 있다.
    ///    조회 직후라면 서버가 공휴일까지 반영해 준 `EnforcementZone.serverStatus` 가 더 정확하다.
    func status(at date: Date = .now) -> RestrictionStatus {
        let calendar = Self.koreaCalendar
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return day(forWeekday: components.weekday ?? 2).status(atMinutes: minutes)
    }

    /// `Calendar` 의 weekday (1=일요일 … 7=토요일) 로 그날 규칙을 고른다.
    func day(forWeekday weekday: Int) -> DayRestriction {
        switch weekday {
        case 1:  return holiday
        case 7:  return saturday
        default: return self.weekday
        }
    }

    /// 화면에 보여줄 요약 문구 (예: "평일 08:00~20:00 · 토 09:00~18:00").
    var summary: String {
        var parts: [String] = []
        if let text = weekday.prohibitedDescription { parts.append("평일 \(text)") }
        if let text = saturday.prohibitedDescription { parts.append("토 \(text)") }
        if let text = holiday.prohibitedDescription { parts.append("일·공휴일 \(text)") }
        return parts.isEmpty ? "상시 금지 아님" : parts.joined(separator: " · ")
    }
}

// MARK: - 클라이언트

protocol EnforcementAPIClientProtocol {
    /// 목적지 주변 주정차 금지구역을 조회한다.
    ///
    /// 검색 반경은 서버에서 2km 로 고정되어 있어 인자로 받지 않는다.
    /// (`JunctionServerConfiguration.fixedSearchRadiusMeters`)
    func fetchEnforcementZones(around coordinate: NaverCoordinate) async throws -> [EnforcementZone]
}

struct EnforcementAPIClient: EnforcementAPIClientProtocol {

    private let runner: JunctionServerRequestRunner
    private let configuration: JunctionServerConfiguration

    init(configuration: JunctionServerConfiguration = .default,
         httpClient: JunctionServerHTTPClient = URLSessionJunctionServerHTTPClient()) {
        self.configuration = configuration
        self.runner = JunctionServerRequestRunner(configuration: configuration, httpClient: httpClient)
    }

    func fetchEnforcementZones(around coordinate: NaverCoordinate) async throws -> [EnforcementZone] {
        let request = try runner.makeDestinationRequest(path: configuration.parkingRestrictionsPath,
                                                        coordinate: coordinate)
        let dto = try await runner.send(request, as: ParkingRestrictionsResponseDTO.self)
        // 좌표가 하나도 없는 구간은 지도에도 못 그리고 거리 계산도 안 되므로 버린다.
        return dto.restrictions.compactMap(Self.makeZone(from:))
    }

    // MARK: - Mapping

    private static func makeZone(from dto: ParkingRestrictionsResponseDTO.RestrictionDTO) -> EnforcementZone? {
        guard !dto.path.isEmpty else { return nil }

        return EnforcementZone(
            roadName: dto.roadName,
            detailLocation: dto.detailLocation,
            kind: EnforcementZone.Kind(apiName: dto.restrictionType.name),
            typeCode: dto.restrictionType.code,
            koreanTypeName: dto.restrictionType.koreanName,
            typeDescription: dto.restrictionType.description,
            directionCode: dto.directionCode,
            serverStatus: RestrictionStatus(apiValue: dto.status),
            distanceFromDestinationMeters: dto.distanceMeters,
            path: dto.path,
            schedule: makeSchedule(from: dto.restriction)
        )
    }

    private static func makeSchedule(from dto: ParkingRestrictionsResponseDTO.ScheduleDTO) -> RestrictionSchedule {
        RestrictionSchedule(weekday: makeDay(from: dto.weekday),
                            saturday: makeDay(from: dto.saturday),
                            holiday: makeDay(from: dto.holiday),
                            holidaySeasonAllowed: dto.holidaySeasonAllowed)
    }

    private static func makeDay(from dto: ParkingRestrictionsResponseDTO.DayDTO) -> DayRestriction {
        DayRestriction(prohibited: makeWindows(from: dto.prohibited),
                       temporarilyAllowed: makeWindows(from: dto.temporarilyAllowed))
    }

    /// 시간 구간을 만든다.
    ///
    /// 원본 데이터가 하루에 여러 구간을 두는 경우가 있어 `+` 로 이어 붙인 문자열이 온다.
    /// 예) start `"08:00+11:30+18:00"`, end `"09:00+13:30+20:00"`
    ///     → 08:00~09:00, 11:30~13:30, 18:00~20:00
    private static func makeWindows(from dto: ParkingRestrictionsResponseDTO.TimeRangeDTO) -> [TimeWindow] {
        guard let start = dto.start, let end = dto.end else { return [] }

        let starts = start.split(separator: "+").map(String.init)
        let ends = end.split(separator: "+").map(String.init)
        // 시작/종료 개수가 어긋나면 짝이 맞는 데까지만 쓴다. (원본 데이터 품질 대비)
        return zip(starts, ends)
            .compactMap { TimeWindow(start: $0, end: $1) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - DTO

/// `GET /api/v1/parking-restrictions` 응답.
struct ParkingRestrictionsResponseDTO: Decodable {

    var restrictions: [RestrictionDTO]

    struct RestrictionDTO: Decodable {
        var roadName: String
        var detailLocation: String
        var restrictionType: RestrictionTypeDTO
        var directionCode: String?
        /// `RESTRICTED` / `TEMPORARILY_ALLOWED` / `INACTIVE`
        var status: String
        var distanceMeters: Double
        /// `{latitude, longitude}` 객체 배열. 네이버 REST 의 `[경도, 위도]` 배열이 아니다.
        var path: [JunctionServerCoordinateDTO]
        var restriction: ScheduleDTO
    }

    struct RestrictionTypeDTO: Decodable {
        /// 01=절대, 02=탄력, 03=혼용
        var code: String?
        /// `ABSOLUTE` / `FLEXIBLE` / `MIXED` / `UNKNOWN`
        var name: String
        var koreanName: String
        var description: String
    }

    struct ScheduleDTO: Decodable {
        var weekday: DayDTO
        var saturday: DayDTO
        var holiday: DayDTO
        var holidaySeasonAllowed: Bool
    }

    struct DayDTO: Decodable {
        var prohibited: TimeRangeDTO
        var temporarilyAllowed: TimeRangeDTO
    }

    struct TimeRangeDTO: Decodable {
        /// `"HH:mm"`. 구간이 여럿이면 `"08:00+11:30"` 처럼 `+` 로 이어진다.
        var start: String?
        var end: String?
    }
}
