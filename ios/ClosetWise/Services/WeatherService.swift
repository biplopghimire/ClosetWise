import CoreLocation
import Foundation
import Observation

/// Finds the user's rough location and today's weather there, so outfit ideas suit the day.
///
/// Privacy: location is asked for only when the user taps "Use my location", the coordinates are
/// rounded to about 1 km before they go to Open-Meteo (a free, keyless weather API), and they are
/// never stored or synced. Only the resulting weather (and town name) is kept on the phone.
@MainActor
@Observable
final class WeatherService: NSObject {
    static let shared = WeatherService()

    enum Access { case notAsked, denied, allowed }

    private(set) var access: Access = .notAsked
    private(set) var loading = false
    private(set) var lastError: String?
    private(set) var current: WeatherNow? {
        didSet { store?.weather = current }
    }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var locationWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    @ObservationIgnored private weak var store: ClosetStore?
    @ObservationIgnored private let cacheKey = "weather.last"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        access = Self.access(for: manager.authorizationStatus)
        if let data = UserDefaults.standard.data(forKey: cacheKey), let cached = try? JSONDecoder().decode(WeatherNow.self, from: data),
           Date.now.timeIntervalSince(cached.fetchedAt) < 3 * 3600 {
            current = cached
        }
    }

    /// Called at launch and when the app comes back: refreshes if allowed and the forecast is stale.
    func attach(_ store: ClosetStore) async {
        self.store = store
        store.weather = current
        guard access == .allowed else { return }
        if let current, Date.now.timeIntervalSince(current.fetchedAt) < 30 * 60 { return }
        await refresh()
    }

    /// The user tapped "Use my location".
    func requestAccess() async {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return   // the delegate refreshes once they answer
        }
        await refresh()
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        lastError = nil
        defer { loading = false }
        guard let location = await currentLocation() else {
            if access == .allowed { lastError = "Couldn't find your location" }
            return
        }
        do {
            var weather = try await Self.fetch(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            weather.place = await Self.placeName(for: location)
            current = weather
            if let data = try? JSONEncoder().encode(weather) { UserDefaults.standard.set(data, forKey: cacheKey) }
        } catch {
            lastError = "Couldn't get the weather"
        }
    }

    // MARK: Location

    private func currentLocation() async -> CLLocation? {
        guard access == .allowed else { return nil }
        return await withCheckedContinuation { continuation in
            locationWaiters.append(continuation)
            if locationWaiters.count == 1 { manager.requestLocation() }
        }
    }

    private func finishLocation(_ location: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters = []
        waiters.forEach { $0.resume(returning: location) }
    }

    private static func access(for status: CLAuthorizationStatus) -> Access {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        case .denied, .restricted: .denied
        default: .notAsked
        }
    }

    private static func placeName(for location: CLLocation) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return marks?.first?.locality ?? marks?.first?.administrativeArea
    }

    // MARK: Open-Meteo

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let wind_speed_10m: Double
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]
        }
        let current: Current
        let daily: Daily
    }

    private static func fetch(latitude: Double, longitude: Double) async throws -> WeatherNow {
        // ~1 km precision is plenty for weather and keeps the exact location on the phone.
        func rounded(_ v: Double) -> String { String(format: "%.2f", v) }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: rounded(latitude)),
            .init(name: "longitude", value: rounded(longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return WeatherNow(tempC: r.current.temperature_2m, feelsC: r.current.apparent_temperature,
                          highC: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
                          lowC: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
                          precipChance: (r.daily.precipitation_probability_max.first ?? 0) ?? 0,
                          code: r.current.weather_code, windKmh: r.current.wind_speed_10m,
                          place: nil, fetchedAt: .now)
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            let before = self.access
            self.access = Self.access(for: status)
            if before != .allowed && self.access == .allowed { await self.refresh() }
            if self.access == .denied { self.finishLocation(nil) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finishLocation(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishLocation(nil) }
    }
}
