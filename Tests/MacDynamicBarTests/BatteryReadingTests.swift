import IOKit.ps
import Testing

@testable import MacDynamicBar

@Test func onlyValidInternalPowerReadingsCanGenerateBatteryEvents() {
  var values: [String: Any] = [
    kIOPSTypeKey: kIOPSInternalBatteryType,
    kIOPSCurrentCapacityKey: 25, kIOPSMaxCapacityKey: 50,
    kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue, kIOPSIsChargingKey: false,
  ]
  #expect(MacBatterySnapshot.parse(values)?.percentage == 50)
  values[kIOPSMaxCapacityKey] = 0
  #expect(MacBatterySnapshot.parse(values) == nil)
  values[kIOPSMaxCapacityKey] = 50
  values[kIOPSCurrentCapacityKey] = -1
  #expect(MacBatterySnapshot.parse(values) == nil)
  values[kIOPSCurrentCapacityKey] = 25
  values[kIOPSTypeKey] = "UPS"
  #expect(MacBatterySnapshot.parse(values) == nil)
  values[kIOPSTypeKey] = kIOPSInternalBatteryType
  values.removeValue(forKey: kIOPSPowerSourceStateKey)
  #expect(MacBatterySnapshot.parse(values) == nil)
}
