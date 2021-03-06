//
//  IDS
//  Pods
//
//  Created by Kevin Tallevi on 09/11/2017.
//
//

import Foundation
import CoreBluetooth
import CCBluetooth
import CCToolbox

var thisIDS : IDS?

@objc public protocol IDSProtocol {
    func IDSFeatures(features: IDSFeatures)
    func IDSStatusChanged(statusChanged: IDSStatusChanged)
    func IDSStatusUpdate(status: IDSStatus)
    func IDSAnnunciationStatusUpdate(annunciation: IDSAnnunciationStatus)
}

@objc public protocol IDSBatteryProtocol {
    func IDSBatteryLevel(level: UInt8)
}

@objc public protocol IDSDeviceInformationProtocol {
    func IDSSerialNumber(serialNumber : String)
    func IDSModelNumber(modelNumber: String)
    func IDSManufacturer(manufacturerName: String)
}

@objc public protocol IDSConnectionProtocol {
    func IDSConnected(ids: CBPeripheral)
    func IDSDisconnected(ids: CBPeripheral)
}

@objc public protocol IDSDiscoveryProtocol {
    func IDSDiscovered(IDSDevice:CBPeripheral)
}

public class IDS : NSObject {
    public weak var idsDelegate : IDSProtocol?
    public weak var idsConnectionDelegate: IDSConnectionProtocol?
    public weak var idsDiscoveryDelegate: IDSDiscoveryProtocol?
    public weak var idsBatteryDelete: IDSBatteryProtocol?
    public weak var idsDeviceInformationDelete: IDSDeviceInformationProtocol?
    public var historyEvents: Array<IDSHistoryEvent> = Array<IDSHistoryEvent>()
    
    var peripheral : CBPeripheral? {
        didSet {
            if (peripheral != nil) { // don't wipe the UUID when we disconnect and clear the peripheral
                uuid = peripheral?.identifier.uuidString
                name = peripheral?.name
            }
        }
    }
    
    public var serviceUUIDString: String = "1829"
    public var autoEnableNotifications: Bool = true
    public var allowDuplicates: Bool = false
    public var batteryProfileSupported: Bool = false
    public var idsFeatures: IDSFeatures!
    public var idsStatusChanged: IDSStatusChanged!
    public var idsStatus: IDSStatus!
    public var idsAnnunciation: IDSAnnunciationStatus!
    
    public var currentTimeServiceSupported: Bool = false
    public var batteryServiceSupported: Bool = false
    public var immediateAlertServiceSupported: Bool = false
    public var bondManagementServiceSupported: Bool = false
    
    var peripheralNameToConnectTo : String?
    var servicesAndCharacteristics : [String: [CBCharacteristic]] = [:]
    var allowedToScanForPeripherals:Bool = false
    
    public internal(set) var uuid: String?
    public internal(set) var name: String? // local name
    public internal(set) var manufacturerName : String?
    public internal(set) var modelNumber : String?
    public internal(set) var serialNumber : String?
    public internal(set) var firmwareVersion : String?
    public internal(set) var softwareVersion : String?
    public internal(set) var hardwareVersion : String?
    
    public class func sharedInstance() -> IDS {
        if thisIDS == nil {
            thisIDS = IDS()
        }
        return thisIDS!
    }
    
    public override init() {
        super.init()
        print("IDS#init")
        self.configureBluetoothParameters()
    }
    
    func configureBluetoothParameters() {
        Bluetooth.sharedInstance().allowDuplicates = false
        Bluetooth.sharedInstance().autoEnableNotifications = true
        Bluetooth.sharedInstance().bluetoothDelegate = self
        Bluetooth.sharedInstance().bluetoothPeripheralDelegate = self
        Bluetooth.sharedInstance().bluetoothServiceDelegate = self
        Bluetooth.sharedInstance().bluetoothCharacteristicDelegate = self
    }
    
    func parseFeaturesResponse(data: NSData) {
        print("parseFeaturesResponse")
        self.idsFeatures = IDSFeatures(data: data)
        idsDelegate?.IDSFeatures(features: self.idsFeatures)
    }
    
    func parseIDSStatusChanged(data: NSData) {
        print("parseIDSStatusChanged")
        self.idsStatusChanged = IDSStatusChanged(data: data)
        idsDelegate?.IDSStatusChanged(statusChanged: self.idsStatusChanged)
    }
    
    func parseIDSStatus(data: NSData) {
        print("parseIDSStatus")
        self.idsStatus = IDSStatus(data: data)
        idsDelegate?.IDSStatusUpdate(status: self.idsStatus)
    }
    
    func parseIDSAnnunciation(data: NSData) {
        print("parseIDSAnnunciation")
        self.idsAnnunciation = IDSAnnunciationStatus(data: data)
        idsDelegate?.IDSAnnunciationStatusUpdate(annunciation: self.idsAnnunciation)
    }

    func parseIDSStatusReaderControlPointCharacteristic(data: NSData) {
        print("parseIDSStatusReaderControlPointCharacteristic")
        IDSStatusReaderControlPoint.sharedInstance().parseIDSStatusReaderControlPointResponse(data: data)
    }
    
    func parseRACPCharacteristic(data: NSData) {
        IDSRecordAccessControlPoint.sharedInstance().parseRACPReponse(data: data)
    }
    
    func parseHistoryCharacteristic(data: NSData) {
        let historyEvent = IDSHistoryEvent(data: data)
        self.historyEvents.append(historyEvent)
    }
    
    func parseIDSCommandDataCharacteristic(data: NSData) {
        print("parseIDSCommandDataCharacteristic")
        IDSCommandData.sharedInstance().parseIDSCommandDataResponse(data: data)
    }

    func parseIDSCommandControlPointCharacteristic(data: NSData) {
        print("parseIDSCommandControlPointCharacteristic")
        IDSCommandControlPoint.sharedInstance().parseIDSCommandControlPointResponse(data: data)
    }
    
    func crcIsValid(data: NSData) -> Bool {
        let packet = (data.subdata(with: NSRange(location:0, length: data.length - 2)) as NSData?)
        let packetCRC = (data.subdata(with: NSRange(location:data.length - 2, length: 2)) as NSData?)
        let calculatedCRC: NSData = (packet?.crcMCRF4XX)!
        
        if packetCRC == calculatedCRC {
            return true
        }
        print("Invalid CRC")
        print("Calculated CRC: \(String(describing: calculatedCRC)) , Packet CRC: \(String(describing: packetCRC))")
        
        return false
    }
    
    func featureCRCIsValid(data: NSData) -> Bool {
        let packet = (data.subdata(with: NSRange(location:2, length: data.length - 2)) as NSData?)
        let packetCRC = (data.subdata(with: NSRange(location:0, length: 2)) as NSData?)
        let calculatedCRC: NSData = (packet?.crcMCRF4XX)!
        
        if packetCRC == calculatedCRC {
            return true
        }
        print("Invalid CRC")
        print("Calculated CRC: \(String(describing: calculatedCRC)) , Packet CRC: \(String(describing: packetCRC))")
        
        return false
    }
    
    public func readStatus() {
        if let peripheral = self.peripheral {
            Bluetooth.sharedInstance().readCharacteristic(peripheral.findCharacteristicByUUID(idsStatusCharacteristic)!)
        }
    }
    
    public func readBatteryLevel() {
        if let peripheral = self.peripheral {
            Bluetooth.sharedInstance().readCharacteristic(peripheral.findCharacteristicByUUID(batteryLevelCharacteristic)!)
        }
    }
}

extension IDS: BluetoothProtocol {
    public func scanForIDSDevices() {
        if(self.allowedToScanForPeripherals) {
            Bluetooth.sharedInstance().startScanning(self.allowDuplicates, serviceUUIDString: "1829")
        }
    }
    
    public func bluetoothIsAvailable() {
        self.allowedToScanForPeripherals = true
        
        if let peripheral = self.peripheral {
            Bluetooth.sharedInstance().connectPeripheral(peripheral)
        } else {
            Bluetooth.sharedInstance().startScanning(self.allowDuplicates, serviceUUIDString: "1829")
        }
    }
    
    public func bluetoothIsUnavailable() {
        
    }
    
    public func bluetoothError(_ error:Error?) {
        
    }
}

extension IDS: BluetoothPeripheralProtocol {
    public func didDiscoverPeripheral(_ peripheral:CBPeripheral) {
        print("IDS#didDiscoverPeripheral")
        
        self.peripheral = peripheral
        if (self.peripheralNameToConnectTo != nil) {
            if (peripheral.name == self.peripheralNameToConnectTo) {
                Bluetooth.sharedInstance().connectPeripheral(peripheral)
            }
        } else {
            idsDiscoveryDelegate?.IDSDiscovered(IDSDevice: peripheral)
        }
    }
    
    public func didConnectPeripheral(_ cbPeripheral:CBPeripheral) {
        print("IDS#didConnectPeripheral")
        self.peripheral = cbPeripheral
        idsConnectionDelegate?.IDSConnected(ids: cbPeripheral)
        IDSStatusReaderControlPoint.sharedInstance().peripheral = cbPeripheral
        IDSCommandControlPoint.sharedInstance().peripheral = cbPeripheral
        IDSRecordAccessControlPoint.sharedInstance().peripheral = cbPeripheral
        IDSDateTime.sharedInstance().peripheral = cbPeripheral
        Bluetooth.sharedInstance().discoverAllServices(cbPeripheral)
    }
    
    public func didDisconnectPeripheral(_ cbPeripheral: CBPeripheral) {
        print("IDS#didDisconnectPeripheral")
        self.peripheral = nil
        IDSStatusReaderControlPoint.sharedInstance().peripheral = nil
        IDSCommandControlPoint.sharedInstance().peripheral = nil
        IDSDateTime.sharedInstance().peripheral = nil
        idsConnectionDelegate?.IDSDisconnected(ids: cbPeripheral)
    }
}

extension IDS: BluetoothServiceProtocol {
    public func didDiscoverServices(_ services: [CBService]) {
        print("IDS#didDiscoverServices - \(services)")
    }
    
    public func didDiscoverServiceWithCharacteristics(_ service:CBService) {
        print("IDS#didDiscoverServiceWithCharacteristics - \(service.uuid.uuidString)")
        servicesAndCharacteristics[service.uuid.uuidString] = service.characteristics
        
        if (service.uuid.uuidString == "1805") {
            currentTimeServiceSupported = true
        }
        if (service.uuid.uuidString == "180F") {
            batteryProfileSupported = true
        }
        if (service.uuid.uuidString == "1802") {
            immediateAlertServiceSupported = true
        }
        if (service.uuid.uuidString == "181E") {
            bondManagementServiceSupported = true
        }
        
        for characteristic in service.characteristics! {
            if characteristic.properties.contains(CBCharacteristicProperties.read) {
                print("reading characteristic \(characteristic.uuid.uuidString)")
                DispatchQueue.global(qos: .background).async {
                    self.peripheral?.readValue(for: characteristic)
                }
            }
        }
    }
}

extension IDS: BluetoothCharacteristicProtocol {
    public func didUpdateValueForCharacteristic(_ cbPeripheral: CBPeripheral, characteristic: CBCharacteristic) {
        print("IDS#didUpdateValueForCharacteristic: \(characteristic) value:\(String(describing: characteristic.value))")
        
        if(characteristic.uuid.uuidString == idsFeaturesCharacteristic) {
            if(featureCRCIsValid(data: characteristic.value! as NSData)) {
                self.parseFeaturesResponse(data: characteristic.value! as NSData)
            }
        }
        if(characteristic.uuid.uuidString == idsStatusChangedCharacteristic) {
            if(crcIsValid(data: characteristic.value! as NSData)) {
                self.parseIDSStatusChanged(data: characteristic.value! as NSData)
            }
        }
        if(characteristic.uuid.uuidString == idsStatusCharacteristic) {
            if(crcIsValid(data: characteristic.value! as NSData)) {
                self.parseIDSStatus(data: characteristic.value! as NSData)
            }
        }
        if(characteristic.uuid.uuidString == idsAnnunciationStatusCharacteristic) {
            if(crcIsValid(data: characteristic.value! as NSData)) {
                self.parseIDSAnnunciation(data: characteristic.value! as NSData)
            }
        }
        if(characteristic.uuid.uuidString == idsStatusReaderControlPointCharacteristic) {
            if(crcIsValid(data: characteristic.value! as NSData)) {
                self.parseIDSStatusReaderControlPointCharacteristic(data: characteristic.value! as NSData)
            }
        }
        if(characteristic.uuid.uuidString == idsCommandDataCharacteristic) {
            if(crcIsValid(data: characteristic.value! as NSData)) {
                self.parseIDSCommandDataCharacteristic(data: characteristic.value! as NSData)
            }
        }
        if(characteristic.uuid.uuidString == idsCommandControlPointCharacteristic) {
            if(crcIsValid(data: characteristic.value! as NSData)) {
                self.parseIDSCommandControlPointCharacteristic(data: characteristic.value! as NSData)
            }
        }
        if(characteristic.uuid.uuidString == recordAccessControlPointCharacteristic) {
            self.parseRACPCharacteristic(data: characteristic.value! as NSData)
        }
        if(characteristic.uuid.uuidString == idsHistoryDataCharacteristic) {
            self.parseHistoryCharacteristic(data: characteristic.value! as NSData)
        }
        if(characteristic.uuid.uuidString == batteryLevelCharacteristic) {
            idsBatteryDelete?.IDSBatteryLevel(level: characteristic.value![0])
        }
        if(characteristic.uuid.uuidString == manufacturerNameCharacteristic) {
            self.manufacturerName = String(data: characteristic.value!, encoding: .utf8)
            print("manufacturerName: \(String(describing: self.manufacturerName))")
            idsDeviceInformationDelete?.IDSManufacturer(manufacturerName: self.manufacturerName!)
        }
        if(characteristic.uuid.uuidString == firmwareRevisionStringCharacteristic) {
            self.firmwareVersion = String(data: characteristic.value!, encoding: .utf8)
            print("firmwareVersion: \(String(describing: self.firmwareVersion))")
        }
        if(characteristic.uuid.uuidString == modelNumberCharacteristic) {
            self.modelNumber = String(data: characteristic.value!, encoding: .utf8)
            print("modelNumber: \(String(describing: self.modelNumber))")
            idsDeviceInformationDelete?.IDSModelNumber(modelNumber: self.modelNumber!)
        }
        if(characteristic.uuid.uuidString == serialNumberCharacteristic) {
            self.serialNumber = String(data: characteristic.value!, encoding: .utf8)
            print("serialNumber: \(String(describing: self.serialNumber))")
            idsDeviceInformationDelete?.IDSSerialNumber(serialNumber: self.serialNumber!)
        }
    }
    
    public func didUpdateNotificationStateFor(_ characteristic:CBCharacteristic) {
        print("IDS#didUpdateNotificationStateFor characteristic: \(characteristic.uuid.uuidString)")
    }
    
    public func didWriteValueForCharacteristic(_ cbPeripheral: CBPeripheral, didWriteValueFor descriptor:CBDescriptor) {
    }
}
