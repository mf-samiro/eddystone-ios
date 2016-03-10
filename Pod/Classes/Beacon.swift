import CoreBluetooth

public class Beacon {
    
    //MARK: Enumerations
    public enum SignalStrength: Int {
        case Excellent
        case VeryGood
        case Good
        case Low
        case VeryLow
        case NoSignal
        case Unknown
    }
    
    //MARK: Frames
    var frames: (
        url: UrlFrame?,
        uid: UidFrame?,
        tlm: TlmFrame?
    ) = (nil,nil,nil)
    
    public var urlIdentifier: NSURL {
        get {
            if (frames.url != nil)
            {
                return frames.url!.url
            }
            else
            {
                return NSURL()
            }
        }
    }
    
    //MARK: Properties
    public var txPower: Int
    public var rssiValid: Double
    public var rssiBrut: Double
    public var identifier: String
    public var rssi: Double {
        get {
            var totalRssi: Double = 0
            for rssi in self.rssiBuffer {
                totalRssi += rssi
            }
            
            let average: Double = totalRssi / Double(self.rssiBuffer.count)
            return average
            //return self.rssiBrut
        }
    }
    public var signalStrength: SignalStrength = .Unknown
    var rssiBuffer = [Double]()
    var rssiBuffer10 = [Double]()
    public var distance: Double {
        get {
            //return Beacon.calculateAccuracy(txPower: self.txPower, rssi: self.rssi)
            return Beacon.calculateDistance(self.txPower, rssi: self.rssi)
            //return Beacon.calculateDistance(-21, rssi: -89.0)
        }
    }
    
    //MARK: Initializations
    init(rssi: Double, txPower: Int, identifier: String) {
        self.txPower = txPower
        self.identifier = identifier
        self.rssiBrut = rssi
        self.rssiValid = rssi
        
        self.updateRssi(rssi)
    }
    
    //MARK: Delegate
    var delegate: BeaconDelegate?
    func notifyChange() {
        self.delegate?.beaconDidChange()
    }
    
    //MARK: Functions
    func updateRssi(newRssi: Double) -> Bool {
        self.rssiBrut = newRssi
        if (newRssi <= 20.0 && newRssi >= -100.0)
        {
            self.rssiValid = newRssi
            self.rssiBuffer.insert(newRssi, atIndex: 0)
            self.rssiBuffer10.insert(newRssi, atIndex: 0)
        }
        
        if self.rssiBuffer.count >= 20 {
            //self.rssiBuffer.sortInPlace()
            //self.rssiBuffer.removeFirst()
            self.rssiBuffer.removeLast()
        }
        
        if self.rssiBuffer10.count >= 20 {
            //self.rssiBuffer10.sortInPlace()
            //self.rssiBuffer10.removeFirst()
            self.rssiBuffer10.removeLast()
        }
        
        let signalStrength = Beacon.calculateSignalStrength(self.distance)
        if signalStrength != self.signalStrength {
            self.signalStrength = signalStrength
            self.notifyChange()
        }
        
        return false
    }
    
    class func calculateDistance(txPower: Int, rssi: Double) -> Double {
        return pow(10, ((Double(txPower) - rssi) - 41) / 20.0);
    }
    
    //MARK: Calculations
    class func calculateAccuracy(txPower txPower: Int, rssi: Double) -> Double {
        if rssi == 0 {
            return 0
        }
        
        let ratio: Double = rssi / Double(txPower)
        if ratio < 1 {
            return pow(ratio, 10)
        } else {
            return 0.89976 * pow(ratio, 7.7095) + 0.111
        }
        
    }
    
    class func calculateSignalStrength(distance: Double) -> SignalStrength {
        switch distance {
        case 0...24999:
            return .Excellent
        case 25000...49999:
            return .VeryGood
        case 50000...74999:
            return .Good
        case 75000...99999:
            return .Low
        default:
            return .VeryLow
        }
    }
    
    func byteConversion(bytes: [UInt8]) -> [Byte]?{
        return bytes.map { byte in
            return Byte(byte)
        }
    }
    
    //MARK: Advertisement Data
    func parseAdvertisementData(advertisementData: [NSObject : AnyObject], rssi: Double) {
        self.updateRssi(rssi)
        let byteTemp = Beacon.bytesFromAdvertisementData(advertisementData)
        if let bytes = byteConversion(byteTemp!) {
            if let type = Beacon.frameTypeFromBytes(bytes) {
                switch type {
                case .URL:
                    if let frame = UrlFrame.frameWithBytes(bytes) {
                        if frame.url != self.frames.url?.url {
                            self.frames.url = frame
                            log("Parsed URL Frame with url: \(frame.url)")
                            self.notifyChange()
                        }
                    }
                case .UID:
                    if let frame = UidFrame.frameWithBytes(bytes) {
                        if frame.uid != self.frames.uid?.uid {
                            self.frames.uid = frame
                            log("Parsed UID Frame with uid: \(frame.uid)")
                            self.notifyChange()
                        }
                    }
                case .TLM:
                    if let frame = TlmFrame.frameWithBytes(bytes) {
                        self.frames.tlm = frame
                        log("Parsed TLM Frame with battery: \(frame.batteryVolts) temperature: \(frame.temperature) advertisement count: \(frame.advertisementCount) on time: \(frame.onTime)")
                        self.notifyChange()
                    }
                }
            }
        }
    }
    
    //MARK: Bytes
    class func beaconWithAdvertisementData(advertisementData: [NSObject : AnyObject], rssi: Double, identifier: String) -> Beacon? {
        var txPower: Int?
        //var type: FrameType?

        if let bytes = Beacon.bytesFromAdvertisementData(advertisementData) {
            //type = Beacon.frameTypeFromBytes(bytes)
            txPower = Beacon.txPowerFromBytes(bytes)
            
            if let txPower = txPower /*where type != nil*/ {
                let beacon = Beacon(rssi: rssi, txPower: txPower, identifier: identifier)
                beacon.parseAdvertisementData(advertisementData, rssi: rssi)
                return beacon
            }
            
        }
        
        return nil
    }
    
    class func bytesFromAdvertisementData(advertisementData: [NSObject : AnyObject]) -> [UInt8]? {
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [NSObject: AnyObject] {
            if let urlData = serviceData[Scanner.eddystoneServiceUUID] as? NSData {
                let count = urlData.length
                var bytes = [UInt8](count: count, repeatedValue: 0)
                urlData.getBytes(&bytes, length:count)
                /*return bytes.map { byte in
                    return Byte(byte)
                }*/
                return bytes
            }
        }
        
        return nil
    }
    
    class func frameTypeFromBytes(bytes: [Byte]) -> FrameType? {
        if bytes.count >= 1 {
            switch bytes[0] {
            case 0:
                return .UID
            case 16:
                return .URL
            case 32:
                return .TLM
            default:
                break
            }
        }
        
        return nil
    }
    
    class func txPowerFromBytes(bytes: [UInt8]) -> Int? {
        if bytes.count >= 2 {
            //if let type = Beacon.frameTypeFromBytes(bytes) {
                //if type == .UID || type == .URL {
                    //return Int(bytes[1])
                    return Int(Int8(bitPattern:bytes[1]))
                //}
            //}
        }
        
        return nil
    }
}

protocol BeaconDelegate {
    func beaconDidChange()
}