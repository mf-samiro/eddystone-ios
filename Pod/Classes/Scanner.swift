import CoreBluetooth

public class Scanner: NSObject {
    
    //MARK: Public
    public class func start(delegate: ScannerDelegate) {
        
        self.shared.centralManager = CBCentralManager(delegate: self.shared, queue: nil)
        self.shared.delegate = delegate
        
    }
    
    //Returns an array of Url objects that are nearby
    public class var nearbyUrls: [Url] {
        get {
            var urls = [Url]()
            
            for beacon in self.beacons {
                if let urlFrame = beacon.frames.url {
                    let url = Url(url: urlFrame.url, signalStrength: beacon.signalStrength, identifier: beacon.identifier)
                    if let tlmFrame = beacon.frames.tlm {
                        url.parseTlmFrame(tlmFrame)
                    }
                    urls.append(url)
                }
            }
            
            return urls
        }
    }
    
    //Returns an array of Uid objects that are nearby
    public class var nearbyUids: [Uid] {
        get {
            var uids = [Uid]()
            
            for beacon in self.beacons {
                if let uidFrame = beacon.frames.uid {
                    let uid = Uid(namespace: uidFrame.namespace, instance: uidFrame.instance, signalStrength: beacon.signalStrength, identifier: beacon.identifier)
                    if let tlmFrame = beacon.frames.tlm {
                        uid.parseTlmFrame(tlmFrame)
                    }
                    uids.append(uid)
                }
            }
            
            return uids
        }
    }
    
    //Returns an array of all nearby Eddystone objects
    public class var nearby: [Generic] {
        get {
            var generics = [Generic]()
            
            for beacon in self.beacons {
                var url: NSURL?
                var namespace: String?
                var instance: String?
                
                if let uidFrame = beacon.frames.uid {
                    namespace = uidFrame.namespace
                    instance = uidFrame.instance
                }
                
                if let urlFrame = beacon.frames.url {
                    url = urlFrame.url
                }
                
                let generic = Generic(url: url, namespace: namespace, instance: instance, signalStrength: beacon.signalStrength, identifier: beacon.identifier)
                if let tlmFrame = beacon.frames.tlm {
                    generic.parseTlmFrame(tlmFrame)
                }
                generics.append(generic)
            }
            
            return generics

        }
    }
    
    //MARK: Singleton
    static let shared = Scanner()
    
    //MARK: Constants
    static let eddystoneServiceUUID = CBUUID(string: "FEAA")
    
    //MARK: Properties
    var centralManager = CBCentralManager()
    var discoveredBeacons = [String: Beacon]()
    var beaconTimers = [String: NSTimer]()
    
    //MARK: Delegate
    var delegate: ScannerDelegate?
    func notifyChange() {
        self.delegate?.eddystoneNearbyDidChange()
    }
    
    //MARK: Internal Class
    public class var beacons: [Beacon] {
        get {
            var orderedBeacons = [Beacon]()
            
            for beacon in self.shared.discoveredBeacons.values {
                orderedBeacons.append(beacon)
            }
            
            orderedBeacons.sortInPlace { beacon1, beacon2 in
                return beacon1.distance < beacon2.distance
            }
            
            return orderedBeacons
        }
    }
    
}

extension Scanner: CBCentralManagerDelegate {
    
    public func centralManagerDidUpdateState(central: CBCentralManager) {
        if central.state == .PoweredOn {
            central.scanForPeripheralsWithServices([Scanner.eddystoneServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        } else {
            log("Bluetooth not powered on. Current state: \(central.state)")
        }
    }
    
    public func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        let identifier = peripheral.identifier.UUIDString

        if let beacon = self.discoveredBeacons[identifier] {
            beacon.parseAdvertisementData(advertisementData, rssi: RSSI.doubleValue)
        } else {
            if let beacon = Beacon.beaconWithAdvertisementData(advertisementData, rssi: RSSI.doubleValue, identifier: identifier) {
                beacon.delegate = self
                self.discoveredBeacons[peripheral.identifier.UUIDString] = beacon
                self.notifyChange()
            }
        }
        
        self.beaconTimers[identifier]?.invalidate()
        self.beaconTimers[identifier] = NSTimer.scheduledTimerWithTimeInterval(10, target: self, selector: Selector("beaconTimerExpire:"), userInfo: identifier, repeats: false)
    }
    
    @objc func beaconTimerExpire(timer: NSTimer) {
        if let identifier = timer.userInfo as? String {
            log("Beacon lost")
            
            self.discoveredBeacons.removeValueForKey(identifier)
            self.notifyChange()
        }
    }
}

extension Scanner: BeaconDelegate {
    
    func beaconDidChange() {
        self.notifyChange()
    }
    
}

//MARK: Protocol
public protocol ScannerDelegate {
    
    func eddystoneNearbyDidChange()
    
}