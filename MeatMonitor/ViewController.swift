//
//  ViewController.swift
//  MeatMonitor
//
//  Created by Joshua Verdejo on 3/28/21.
//

import UIKit
import CoreBluetooth
import CoreData
import EITKitMobile

let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
let characteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
var pts = [[Double]]()
var tri = [[Int]]()
var eit : BP?

class ViewController: UIViewController,  CBPeripheralDelegate, CBCentralManagerDelegate {
    
    // Properties
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var resetButton: UIButton!
    @IBOutlet weak var fatPercentage: UILabel!
    public var myCharacteristic : CBCharacteristic!
    var frameString = ""
    var buffer = ""
    var origin = [Double]()
    var frame = [Double]()
    var frameTag = 200;
    var infoTag = 300;
    override func viewDidLoad() {
        super.viewDidLoad()
        // extract node, element, alpha
        (eit,pts,tri) = mesh_setup(32)
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    
    @IBAction func scanButtonTouched(_ sender: Any) {
        centralManager.stopScan()
        print("Central scanning for", serviceUUID);
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
    }
    
    
    @IBAction func disconnectTouched(_ sender: Any) {
        centralManager?.cancelPeripheralConnection(peripheral!)
    }
    
    @IBAction func resetTouched(_ sender: Any) {
        frame = []
        buffer = ""
        origin = []
        frameString = ""
    }
    
    
    
    func sendText(text: String) {
        if (peripheral != nil && myCharacteristic != nil) {
            let data = text.data(using: .utf8)
            peripheral!.writeValue(data!,  for: myCharacteristic!, type: CBCharacteristicWriteType.withResponse)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // We've found it so stop scan
        self.centralManager.stopScan()
        // Copy the peripheral instance
        self.peripheral = peripheral
        self.peripheral.delegate = self
        
        // Connect!
        self.centralManager.connect(self.peripheral, options: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOff:
            print("Bluetooth is switched off")
        case .poweredOn:
            print("Bluetooth is switched on")
        case .unsupported:
            print("Bluetooth is not supported")
        default:
            print("Unknown state")
        }
    }
    
    // The handler if we do connect succesfully
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral == self.peripheral {
            print("Connected to your board")
            peripheral.discoverServices([serviceUUID])
        }
        connectButton.isEnabled = false
        disconnectButton.isEnabled = true
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from " +  peripheral.name!)
        connectButton.isEnabled = true
        disconnectButton.isEnabled = false
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print(error!)
    }
    @objc func handleFrameSaved(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            print( error.localizedDescription )
        } else {
            print("Saved!")
        }
    }
    
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        myCharacteristic = characteristics[0]
        peripheral.setNotifyValue(true, for: myCharacteristic)
        peripheral.readValue(for: myCharacteristic)
        
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?){
        if let string = String(bytes: myCharacteristic.value!, encoding: .utf8) {
            
            frameString += string
            if string.contains("framef") || string.contains("framei"){
                while (frameString.last! != "i" && frameString.last! != "f"){
                    buffer = String(frameString.last!) + buffer
                    frameString.removeLast()
                }
                if origin.count == 0{
                    origin = parseFrame(frameString)
                }
                else{
                    frame = parseFrame(frameString)
//                    print(origin.count,frame.count)
                    if (frame != origin && frame.count == origin.count){
                        //                        print(origin.count,frame.count)
                        let ds : [Double] = eit!.solve(v1: frame, v0: origin)
                        if (self.view.viewWithTag(frameTag) != nil){
                            self.view.viewWithTag(frameTag)!.removeFromSuperview()
                        }
                        let mesh = mapMeat(ds: ds,pts: pts,tri: tri, w: Double(self.view.frame.width))
                        mesh.tag = frameTag
                        mesh.center = CGPoint(x: self.view.frame.width/2, y: self.view.frame.width)
                        self.view.addSubview(mesh)


                    }
                }
                frameString = buffer
                buffer = ""
                sendText(text: "")
            }
            else{
                sendText(text: "")
            }
            sendText(text: "")
        } else {
            print(myCharacteristic.value!)
            print("not a valid UTF-8 sequence")
        }
        
    }
    func mapMeat(ds:[Double],pts:[[Double]],tri:[[Int]], w: Double) -> (UIView){
        let padding : Double = 10
        let mesh = makeMeatMesh(ds: ds, pts: pts, tri: tri, w: w, padding: padding)
        return (mesh)
    }
    
    func makeMeatMesh(ds:[Double],pts:[[Double]],tri:[[Int]], w: Double, padding: Double) -> (UIView){
        // modified version of MakeMesh in EITKitMobile
        //v1,v2,v3 represent vertex points
        //color is mean of color at each point of vertex
        //minc and maxc are bounds of colors
        //returns the mesh, and the min/max values of the conductivity changes
        let xvals = pts.compactMap({$0[0]})
        let yvals = pts.compactMap({$0[1]})
        let lean = #colorLiteral(red: 0.9620787501, green: 0.540130496, blue: 0.5421358943, alpha: 1)
        let fat = #colorLiteral(red: 1, green: 0.8494106531, blue: 0.8521665931, alpha: 1)
        var fatCount = 0.0
        var meatCount = 0.0
        let (minx,miny,maxx,maxy,minc,maxc) = (xvals.min()!,yvals.min()!,xvals.max()!,yvals.max()!,ds.min()!,ds.max()!)
        var v1,v2,v3 : [Double]
        var c1,c2,c3 : Double
        var x1,x2,x3,y1,y2,y3 : CGFloat
        let mesh = UIView()
        for t in tri{
            v1 = pts[t[0]]
            x1 = transform(x: v1[0], a: minx, b: maxx, c: 0, d: w)
            y1 = transform(x: v1[1], a: miny, b: maxy, c: w, d: 0)
            v2 = pts[t[1]]
            x2 = transform(x: v2[0], a: minx, b: maxx, c: 0, d: w)
            y2 = transform(x: v2[1], a: miny, b: maxy, c: w, d: 0)
            v3 = pts[t[2]]
            x3 = transform(x: v3[0], a: minx, b: maxx, c: 0, d: w)
            y3 = transform(x: v3[1], a: miny, b: maxy, c: w, d: 0)
            c1 = ds[t[0]]
            c2 = ds[t[1]]
            c3 = ds[t[2]]
            let threshold = 0.5
            let meatColor = ((c1+c2+c3)/3 < threshold*maxc) ? lean.cgColor : fat.cgColor
            if (meatColor == fat.cgColor) {fatCount += 1}
            meatCount += 1
            let shape = CAShapeLayer()
            shape.strokeColor = meatColor
            shape.fillColor = meatColor
            
             let path = UIBezierPath()
             path.move(to: CGPoint(x: x1, y: y1))
             path.addLine(to: CGPoint(x: x2, y: y2))
             path.addLine(to: CGPoint(x: x3, y: y3))
             path.addLine(to: CGPoint(x: x1, y: y1))
             path.close()
             shape.path = path.cgPath
             mesh.layer.addSublayer(shape)
        }
        mesh.frame = CGRect(x: 0, y: 0, width: w, height: w)
        print(fatCount/meatCount)
        fatPercentage.text = String(round((fatCount/meatCount)*10000)/100) + "%"
        return (mesh)
    }
}



