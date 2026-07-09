import Foundation
import CoreLocation
import Combine

/// Определяет местоположение через CoreLocation (бесплатно, на устройстве).
/// Одноразовый фикс: город не меняется каждую секунду. При отказе — молчим,
/// приложение остаётся на фоллбэк-локации (Грозный).
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var cityName: String?
    @Published var authorized = false

    /// ISO-код страны и регион (субъект) из reverse-geocode — для выбора метода
    /// расчёта «по региону» (PrayerMethod). Пустые, пока геокодер не ответил.
    @Published var isoCountryCode: String?
    @Published var administrativeArea: String?

    /// Вызывается, когда есть свежие координаты или название города.
    var onUpdate: (() -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer   // для намаза город — с запасом
    }

    /// Спросить разрешение и (если дадут) получить координаты.
    func start() {
        manager.requestWhenInUseAuthorization()
        // На macOS сам по себе requestWhenInUseAuthorization может не показать
        // окно запроса — старт обновлений подталкивает систему спросить.
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            authorized = true
            manager.startUpdatingLocation()
        case .denied, .restricted:
            authorized = false          // остаёмся на фоллбэке
        case .notDetermined:
            break                        // окно запроса уже показано
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        coordinate = loc.coordinate
        manager.stopUpdatingLocation()   // одного фикса достаточно
        onUpdate?()
        reverseGeocode(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // тихо остаёмся на фоллбэке
    }

    private func reverseGeocode(_ loc: CLLocation) {
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self = self else { return }
            let placemark = placemarks?.first
            self.cityName = placemark?.locality
            self.isoCountryCode = placemark?.isoCountryCode
            self.administrativeArea = placemark?.administrativeArea
            self.onUpdate?()
        }
    }

    /// Геокод произвольных (ручных) координат — чтобы для ручной локации тоже
    /// определить страну/регион для авто-выбора метода. Работает независимо от
    /// GPS-разрешения. Результат отдаётся в колбэк; nil-поля при неудаче.
    func geocode(latitude: Double, longitude: Double,
                 completion: @escaping (_ country: String?, _ area: String?, _ city: String?) -> Void) {
        let loc = CLLocation(latitude: latitude, longitude: longitude)
        CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
            let p = placemarks?.first
            completion(p?.isoCountryCode, p?.administrativeArea, p?.locality)
        }
    }
}
