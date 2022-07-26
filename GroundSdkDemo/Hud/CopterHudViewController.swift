// Copyright (C) 2019 Parrot Drones SAS
//
//    Redistribution and use in source and binary forms, with or without
//    modification, are permitted provided that the following conditions
//    are met:
//    * Redistributions of source code must retain the above copyright
//      notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above copyright
//      notice, this list of conditions and the following disclaimer in
//      the documentation and/or other materials provided with the
//      distribution.
//    * Neither the name of the Parrot Company nor the names
//      of its contributors may be used to endorse or promote products
//      derived from this software without specific prior written
//      permission.
//
//    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
//    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
//    PARROT COMPANY BE LIABLE FOR ANY DIRECT, INDIRECT,
//    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
//    OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
//    AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//    OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
//    OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
//    SUCH DAMAGE.

import UIKit
import GroundSdk
import GameController
import CoreLocation
import CoreML
import Vision
import CoreGraphics

import CoreImage
import AVFoundation

typealias CameraData = Vmeta_TimedMetadata

class CopterHudViewController: UIViewController, DeviceViewController {

    private let groundSdk = GroundSdk()
    private var droneUid: String?
    private var drone: Drone?

    private let dimInstrumentAlpha: CGFloat = 0.4

    // formatter for the distance
    private lazy var distanceFormatter: MeasurementFormatter = {
        let distanceFormatter = MeasurementFormatter()
        distanceFormatter.unitOptions = .naturalScale
        distanceFormatter.numberFormatter.maximumFractionDigits = 1
        return distanceFormatter
    }()

    // formatter for the speed
    private lazy var speedFormatter: MeasurementFormatter = {
        let speedFormatter = MeasurementFormatter()
        speedFormatter.unitOptions = .naturalScale
        speedFormatter.unitStyle = .short
        speedFormatter.numberFormatter.maximumFractionDigits = 1
        return speedFormatter
    }()

    private var flyingIndicators: Ref<FlyingIndicators>?
    private var alarms: Ref<Alarms>?
    private var pilotingItf: Ref<ManualCopterPilotingItf>?
    private var pointOfInterestItf: Ref<PointOfInterestPilotingItf>?
    private var returnHomePilotingItf: Ref<ReturnHomePilotingItf>?
    private var followMePilotingItf: Ref<FollowMePilotingItf>?
    private var lookAtPilotingItf: Ref<LookAtPilotingItf>?
    private var gps: Ref<Gps>?
    private var altimeter: Ref<Altimeter>?
    private var compass: Ref<Compass>?
    private var speedometer: Ref<Speedometer>?
    private var batteryInfo: Ref<BatteryInfo>?
    private var attitudeIndicator: Ref<AttitudeIndicator>?
    private var camera: Ref<MainCamera>?
    private var streamServer: Ref<StreamServer>?
    private var cameraLive: Ref<CameraLive>?

    
    var streamSink: StreamSink?
    
    private var refLocation: Ref<UserLocation>?

    private var lastDroneLocation: CLLocation?
    private var lastUserLocation: CLLocation?

    @IBOutlet weak var flyingIndicatorsLabel: UILabel!
    @IBOutlet weak var alarmsLabel: UILabel!
    @IBOutlet weak var handLandImage: UIImageView!
    @IBOutlet weak var emergencyButton: UIButton!
    @IBOutlet weak var takoffLandButton: UIButton!
    @IBOutlet weak var stopPoiButton: UIButton!
    @IBOutlet weak var returnHomeButton: UIButton!
    @IBOutlet weak var joysticksView: UIView!
    @IBOutlet weak var gpsImageView: UIImageView!
    @IBOutlet weak var gpsLabel: UILabel!
    @IBOutlet weak var altimeterView: AltimeterView!
    @IBOutlet weak var verticalSpeedView: VerticalSlider!
    @IBOutlet weak var compassView: CompassView!
    @IBOutlet weak var attitudeIndicatorView: AttitudeIndicatorView!
    @IBOutlet weak var speedometerView: UIView!
    @IBOutlet weak var speedometerLabel: UILabel!
    @IBOutlet weak var droneDistanceLabel: UILabel!
    @IBOutlet weak var droneDistanceView: UIView!
    @IBOutlet weak var droneBatteryLabel: UILabel!
    @IBOutlet weak var droneBatteryView: UIView!
    @IBOutlet weak var zoomVelocitySlider: UISlider!
    @IBOutlet weak var streamView: StreamView!

    let gpsFixedImage = UIImage(named: "ic_gps_fixed.png")
    let gpsNotFixedImage = UIImage(named: "ic_gps_not_fixed.png")

    let takeOffButtonImage = UIImage(named: "ic_flight_takeoff_48pt")
    let landButtonImage = UIImage(named: "ic_flight_land_48pt")
    let handButtonImage = UIImage(named: "ic_flight_hand_48pt")

    func setDeviceUid(_ uid: String) {
        droneUid = uid
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        returnHomeButton.setImage(returnHomeButton.image(for: UIControl.State())?.withRenderingMode(.alwaysTemplate),
            for: .highlighted)
    }

    override func viewWillAppear(_ animated: Bool) {
        resetAllInstrumentsViews()
        // get the drone
        if let droneUid = droneUid {
            drone = groundSdk.getDrone(uid: droneUid) { [unowned self] _ in
                self.dismiss(self)
            }
        }
        if let drone = drone {
            initDroneRefs(drone)
        } else {
            dismiss(self)
        }

        getFacilities()
        listenToGamecontrollerNotifs()
        if GamepadController.sharedInstance.gamepadIsConnected {
            gamepadControllerIsConnected()
        } else {
            gamepadControllerIsDisconnected()
        }

        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        MLModelAction()
        stopListeningToGamecontrollerNotifs()
        GamepadController.sharedInstance.droneUid = self.droneUid
    }

    override func viewWillDisappear(_ animated: Bool) {
        streamView.setStream(stream: nil)
        dropFacilities()
        dropAllInstruments()
        GamepadController.sharedInstance.droneUid = nil

        super.viewWillDisappear(animated)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeLeft
    }

    private func resetAllInstrumentsViews() {
        updateFlyingIndicatorLabel(nil)
        updateAlarmsLabel(nil)
        updateHandLandImage(nil)
        updateReturnHomeButton(nil)
        updateAltimeter(nil)
        updateHeading(nil)
        updateSpeedometer(nil)
        updateBatteryInfo(nil)
        updateAttitudeIndicator(nil)
        updateGroundDistance()
    }

    private func initDroneRefs(_ drone: Drone) {
        flyingIndicators = drone.getInstrument(Instruments.flyingIndicators) { [unowned self] flyingIndicators in
            self.updateFlyingIndicatorLabel(flyingIndicators)
            self.updateHandLandImage(flyingIndicators)
        }

        alarms = drone.getInstrument(Instruments.alarms) { [unowned self] alarms in
            self.updateAlarmsLabel(alarms)
        }

        pilotingItf = drone.getPilotingItf(PilotingItfs.manualCopter) { [unowned self] pilotingItf in
            self.updateTakoffLandButton(pilotingItf)
            if let pilotingItf = pilotingItf {
                self.verticalSpeedView.set(maxValue: Double(pilotingItf.maxVerticalSpeed.value))
                self.verticalSpeedView.set(minValue: Double(-pilotingItf.maxVerticalSpeed.value))
            }
        }

        pointOfInterestItf = drone.getPilotingItf(PilotingItfs.pointOfInterest) { [unowned self] pointOfInterestItf in
            self.updateStopPoiButton(pointOfInterestItf)
        }

        returnHomePilotingItf = drone.getPilotingItf(PilotingItfs.returnHome) { [unowned self] pilotingItf in
            self.updateReturnHomeButton(pilotingItf)
        }

        followMePilotingItf = drone.getPilotingItf(PilotingItfs.followMe) {_ in}

        lookAtPilotingItf = drone.getPilotingItf(PilotingItfs.lookAt) {_ in}

        gps = drone.getInstrument(Instruments.gps) { [unowned self] gps in
            // keep the last location for the drone, in order to compute the ground distance
            if let lastKnownLocation = gps?.lastKnownLocation {
                self.lastDroneLocation = lastKnownLocation
            } else {
                self.lastDroneLocation = nil
            }
            self.updateGpsElements(gps)
            self.updateGroundDistance()
        }

        altimeter = drone.getInstrument(Instruments.altimeter) { [unowned self] altimeter in
            self.updateAltimeter(altimeter)
        }
        compass = drone.getInstrument(Instruments.compass) { [unowned self] compass in
            self.updateHeading(compass)
        }
        speedometer = drone.getInstrument(Instruments.speedometer) { [unowned self] speedometer in
            self.updateSpeedometer(speedometer)
        }
        batteryInfo = drone.getInstrument(Instruments.batteryInfo) { [unowned self] batteryInfo in
            self.updateBatteryInfo(batteryInfo)
        }
        attitudeIndicator = drone.getInstrument(Instruments.attitudeIndicator) { [unowned self] attitudeIndicator in
            self.updateAttitudeIndicator(attitudeIndicator)
        }
        camera = drone.getPeripheral(Peripherals.mainCamera) { [unowned self] camera in
            if let zoom = camera?.zoom {
                self.zoomVelocitySlider.isHidden = !zoom.isAvailable
            }
        }
#if !targetEnvironment(simulator)
        streamServer = drone.getPeripheral(Peripherals.streamServer) { streamServer in
            streamServer?.enabled = true
        }
        if let streamServer = streamServer {
            cameraLive = streamServer.value?.live { stream in  //(source: .frontCamera)
                self.streamView.setStream(stream: stream)
                
                let sinkConfig = YuvSinkCore.config(queue: DispatchQueue.main, listener: self)
                self.streamSink = stream?.openSink(config: sinkConfig)
                print("Sitesee Create and Open Sink")
                _ = stream?.play()
            }
        }
#endif
    }

    
    private var modelUrls: [URL]!
    private var selectedVNModel: VNCoreMLModel?
    private var selectedModel: MLModel?
        
    func setUpMLModel() {
        if #available(iOS 13.0, *) {
            selectedModel = try? yolov7_tiny_640(configuration: MLModelConfiguration()).model
            print("Sitesee Open Model: \(String(describing: selectedModel))")
            selectedVNModel = try? VNCoreMLModel(for: selectedModel!)
            print("Sitesee VNModel \(String(describing: selectedVNModel))")
        }
    }
    
        
    private func runModel(data2: Data) {
        
        // Accessing the document directory for the GroundSDK
        let documentDirectory = FileManager.SearchPathDirectory.documentDirectory

            let userDomainMask = FileManager.SearchPathDomainMask.userDomainMask
            let paths = NSSearchPathForDirectoriesInDomains(documentDirectory, userDomainMask, true)

            if let dirPath = paths.first {
                let imageUrl = URL(fileURLWithPath: dirPath).appendingPathComponent("image_frame_547.jpeg")
                print(imageUrl)
                guard let image = UIImage(contentsOfFile: imageUrl.path) else {print("Sitesee No Image"); return}
                print("Sitesee Original Image: \(image.size)")
                let imageData = image.jpegData(compressionQuality: 0.5)
                guard let newImage = resize_image(image: image, resize_target: 640) else { print("Sitesee No Resize Image"); return}
                print("Sitesee: NewResize Image: \(newImage.size)")
                
                /// TO DO: Turn data2 into RGB
                
                let imsize = 1280*720
                let newimage = UIImage(data: data2.prefix(upTo: imsize))
                //let newimage = CGImageCreate(1280, 720, 8, 8, 8*1280, colorspace, CGBitmapInfo.byteOrderMask(), data2.prefix(through: imsize))   //data2.prefix(upTo: imsize))
                
                /// Jeremy's solution for passing data into ML Model (which has an input parameter of image)
                /*
                let data2: Data
                let dataRGB: Data = getRGB(data2)
                let im: CGImage = CGImage(
                  width: 1280,
                  height: 720,
                  bitsPerComponent: 8,
                  bitsPerPixel: 24,
                  bytesPerRow: 1280 * 3,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
                  provider: data2 as CFData as! CGDataProvider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
                )!
                
                */
                 
                print("the image size is: \(newimage?.size)")
                
                if let pngData = newimage!.pngData()
                {
                   let path = URL(fileURLWithPath: dirPath).appendingPathComponent("SiteSeeImageNew.png")
                    try? pngData.write(to: path)
                    print("Saved the image")
                }
                
                
                let handler = VNImageRequestHandler(cgImage: (newimage?.cgImage)!)
            
                let request = VNCoreMLRequest(model: selectedVNModel!, completionHandler: { (request, error) in
                            print("Sitesee runModel Request: \(request)")
                            print("Sitesee runModel Error: \(error)")
                })
                
                
                do {
                    try handler.perform([request])
                    
                    let observation = request.results?.first
                    print("Sitesee ML Results: \(observation)")
                } catch {
                    print(error)
                }
                
            }

    }
    
    @available(iOS 13.0, *)
    /// pass in the data2 here and start the stream set up
//    func runModelOnStream(){
//        print("Inside the function: \(#function) ")
//        
//        DispatchQueue.global(qos: .background).async {
//                // Initialize the coreML vision model, you can also use VGG16().model, or any other model that takes an image.
//                guard let vnCoreModel = try? VNCoreMLModel(for: yolov7_tiny_640().model) else { return }
//
//                // Build the coreML vision request.
//                let request = VNCoreMLRequest(model: vnCoreModel) { (request, error) in
//                    // We get get an array of VNClassificationObservations back
//                    // This has the fields "confidence", which is the score
//                    // and "identifier" which is the recognized class
//                    guard var results = request.results as? [VNClassificationObservation] else { fatalError("Failure") }
//
//                    // Filter out low scoring results.
//                    results = results.filter({ $0.confidence > 0.01 })
//
//                    DispatchQueue.main.async {
//                        completion(results)
//                    }
//                }
//
//                // Initialize the coreML vision request handler.
//                let handler = VNImageRequestHandler(cgImage: )
//
//                // Perform the coreML vision request.
//                do {
//                    try handler.perform([request])
//                } catch {
//                    print("Error: \(error)")
//                }
//            }
//  
//        let session = AVCaptureSession()
//        CopterHudViewController.createImageClassifier()
//        //print("\(imageClassifierVisionModel)")
//        print("Finished exectuing function create Image Classifier")
//        
//    }
    
    /// - Tag: name
    @available(iOS 13.0, *)
    static func createImageClassifier() -> VNCoreMLModel {
        // Use a default model configuration.
        let defaultConfig = MLModelConfiguration()

        // Create an instance of the image classifier's wrapper class.
        let imageClassifierWrapper = try? yolov7_tiny_640(configuration: defaultConfig);if #available(iOS 13.0, *) {
            let imageClassifierWrapper = try? yolov7_tiny_640(configuration: defaultConfig)
        } else {
            // Fallback on earlier versions
        }

        guard let imageClassifier = imageClassifierWrapper else {
            fatalError("App failed to create an image classifier model instance.")
        }

        // Get the underlying model instance.
        let imageClassifierModel = imageClassifier.model

        // Create a Vision instance using the image classifier's model instance.
        guard let imageClassifierVisionModel = try? VNCoreMLModel(for: imageClassifierModel) else {
            fatalError("App failed to create a `VNCoreMLModel` instance.")
        }

        return imageClassifierVisionModel
    }
    
    
//    func getArrayOfBytesFromImage(imageData:NSData) -> NSMutableArray
//    {
//
//        // the number of elements:
//        let count = imageData.length / sizeof(UInt8)
//
//        // create array of appropriate length:
//        var bytes = [UInt8](count: count, repeatedValue: 0)
//
//        // copy bytes into array
//        imageData.getBytes(&bytes, length:count * sizeof(UInt8))
//
//        var byteArray:NSMutableArray = NSMutableArray()
//
//        for (var i = 0; i < count; i++) {
//            byteArray.addObject(NSNumber(unsignedChar: bytes[i]))
//        }
//
//        return byteArray
//
//
//    }
    
    /*
     
     
     if let image = UIImage(named: "example.jpg") {
         if let data = image.jpegData(compressionQuality: 0.8) {
             let filename = getDocumentsDirectory().appendingPathComponent("copy.png")
             try? data.write(to: filename)
         }
     }
     
     
     
     func savePng(_ image: UIImage) {
         if let pngData = image.pngData(),
             let path = documentDirectoryPath()?.appendingPathComponent("examplePng.png") {
             try? pngData.write(to: path)
         }
     }
     
     
     
     */
    
    let sharedContext = CIContext(options: [.useSoftwareRenderer : false])
    
    func resize_image(image: UIImage, resize_target: CGFloat) -> UIImage? {
        let h = image.size.height
        let w = image.size.width
        let image_max = max(h, w)
        let scale = resize_target / image_max
        let aspectRatio = 3/4
                
        let filter = CIFilter(name: "CILanczosScaleTransform")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(scale, forKey: kCIInputScaleKey)
            filter?.setValue(aspectRatio, forKey: kCIInputAspectRatioKey)

            guard let outputCIImage = filter?.outputImage,
                let outputCGImage = sharedContext.createCGImage(outputCIImage,
                                                                from: outputCIImage.extent)
            else {
                return nil
            }
        let image_resized = UIImage(cgImage: outputCGImage)
         
//      padding image to keep aspect-ratio
        return padding_img(image_resized: image_resized, background_color: (0,0,0))
    }
    
    func padding_img(image_resized: UIImage, background_color: (Int, Int, Int)) -> UIImage {
        let width = image_resized.size.width
        let height = image_resized.size.height
        
        let result = UIImage()
        
        if width == height {
            return image_resized
        }
        
        else if width > height {
//            result = Image.new(image_resized.mode, (width, width), background_color)
//            result.paste(image_resized, (0, (width - height) // 2))
            return result
        }
                                         
        else {
//            result = Image.new(image_resized.mode, (height, height), background_color)
//            result.paste(image_resized, ((height - width) // 2, 0))
            return result
        }
    }
    
    private func dropAllInstruments() {
        flyingIndicators = nil
        alarms = nil
        pilotingItf = nil
        pointOfInterestItf = nil
        returnHomePilotingItf = nil
        lookAtPilotingItf = nil
        gps = nil
        altimeter = nil
        compass = nil
        speedometer = nil
        batteryInfo = nil
        attitudeIndicator = nil
        camera = nil
        streamServer = nil
        cameraLive = nil
    }

    @IBAction func dismiss(_ sender: AnyObject) {
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func leftJoystickUpdate(_ sender: JoystickView) {
        if let pilotingItf = pilotingItf?.value, pilotingItf.state == .active {
            pilotingItf.set(pitch: -sender.value.y)
            pilotingItf.set(roll: sender.value.x)
        } else if let pointOfInterestItf = pointOfInterestItf?.value, pointOfInterestItf.state == .active {
            pointOfInterestItf.set(pitch: -sender.value.y)
            pointOfInterestItf.set(roll: sender.value.x)
        } else if let lookAtPilotingItf = lookAtPilotingItf?.value, lookAtPilotingItf.state == .active {
            lookAtPilotingItf.set(pitch: -sender.value.y)
            lookAtPilotingItf.set(roll: sender.value.x)
        } else if let followMePilotingItf = followMePilotingItf?.value, followMePilotingItf.state == .active {
            followMePilotingItf.set(pitch: -sender.value.y)
            followMePilotingItf.set(roll: sender.value.x)
        }
}

    @IBAction func rightJoystickUpdate(_ sender: JoystickView) {
        if let pilotingItf = pilotingItf?.value, pilotingItf.state == .active {
            pilotingItf.set(verticalSpeed: sender.value.y)
            pilotingItf.set(yawRotationSpeed: sender.value.x)
        } else if let pointOfInterestItf = pointOfInterestItf?.value, pointOfInterestItf.state == .active {
            pointOfInterestItf.set(verticalSpeed: sender.value.y)
        } else if let lookAtPilotingItf = lookAtPilotingItf?.value, lookAtPilotingItf.state == .active {
            lookAtPilotingItf.set(verticalSpeed: sender.value.y)
        } else if let followMePilotingItf = followMePilotingItf?.value, followMePilotingItf.state == .active {
            followMePilotingItf.set(verticalSpeed: sender.value.y)
        }
    }

    @IBAction func emergencyClicked(_ sender: UIButton) {
        if let pilotingItf = pilotingItf?.value {
            pilotingItf.emergencyCutOut()
        }
    }

    @IBAction func takeOffLand(_ sender: UIButton) {
        if let pilotingItf = pilotingItf?.value {
            pilotingItf.smartTakeOffLand()
        }
    }

    @IBAction func stopPointOfInterest(_ sender: Any) {
        if let pointOfInterestItf = pointOfInterestItf?.value, pointOfInterestItf.state == .active {
            _ = pointOfInterestItf.deactivate()
        }
    }

    @IBAction func returnHomeClicked(_ sender: UIButton) {
        if let pilotingItf = returnHomePilotingItf?.value {
            switch pilotingItf.state {
            case .idle:
                _ = pilotingItf.activate()
            case .active:
                _ = pilotingItf.deactivate()
            default:
                break
            }
        }
    }

    @IBAction func zoomVelocityDidChange(_ sender: UISlider) {
        if let zoom = camera?.value?.zoom {
            zoom.control(mode: .velocity, target: Double(sender.value))
        }
    }

    @IBAction func zoomVelocityDidEndEditing(_ sender: UISlider) {
        set(zoomVelocity: 0.0)
    }

    private func set(zoomVelocity: Double) {
        zoomVelocitySlider.value = Float(zoomVelocity)
        zoomVelocitySlider.sendActions(for: .valueChanged)
    }

    private func updateFlyingIndicatorLabel(_ flyingIndicators: FlyingIndicators?) {
        if let flyingIndicators = flyingIndicators {
            if flyingIndicators.state == .flying {
                flyingIndicatorsLabel.text = "\(flyingIndicators.state.description)/" +
                    "\(flyingIndicators.flyingState.description)"
            } else {
                flyingIndicatorsLabel.text = "\(flyingIndicators.state.description)"
            }
        } else {
            flyingIndicatorsLabel.text = ""
        }
    }

    private func updateAlarmsLabel(_ alarms: Alarms?) {
        if let alarms = alarms {
            let text = NSMutableAttributedString()
            let critical = [NSAttributedString.Key.foregroundColor: UIColor.red]
            let warning = [NSAttributedString.Key.foregroundColor: UIColor.orange]
            for kind in Alarm.Kind.allCases {
                let alarm = alarms.getAlarm(kind: kind)
                switch alarm.level {
                case .warning:
                    text.append(NSMutableAttributedString(string: kind.description + " ",
                        attributes: warning))
                case .critical:
                    text.append(NSMutableAttributedString(string: kind.description + " ",
                        attributes: critical))
                default:
                    break
                }

            }
            alarmsLabel.attributedText = text
        } else {
            alarmsLabel.text = ""
        }
    }

    private func updateHandLandImage(_ flyingIndicators: FlyingIndicators?) {
        if let flyingIndicators = flyingIndicators {
            handLandImage.isHidden = !flyingIndicators.isHandLanding
        } else {
            handLandImage.isHidden = true
        }
    }

    private func updateTakoffLandButton(_ pilotingItf: ManualCopterPilotingItf?) {
        if let pilotingItf = pilotingItf, pilotingItf.state == .active {
            takoffLandButton.isHidden = false
            let smartAction = pilotingItf.smartTakeOffLandAction
            switch smartAction {
            case .land:
                takoffLandButton.setImage(landButtonImage, for: .normal)
            case .takeOff:
                takoffLandButton.setImage(takeOffButtonImage, for: .normal)
            case .thrownTakeOff:
                takoffLandButton.setImage(handButtonImage, for: .normal)
            case .none:
                ()
            }
            takoffLandButton.isEnabled = smartAction != .none
        } else {
            takoffLandButton.isEnabled = false
            takoffLandButton.isHidden = true
        }
    }

    private func updateStopPoiButton(_ pilotingItf: PointOfInterestPilotingItf?) {
        if let pilotingItf = pilotingItf, pilotingItf.state == .active {
            stopPoiButton.isHidden = false
        } else {
            stopPoiButton.isHidden = true
        }
    }

    private func updateReturnHomeButton(_ pilotingItf: ReturnHomePilotingItf?) {
        if let pilotingItf = pilotingItf {
            switch pilotingItf.state {
            case .unavailable:
                returnHomeButton.isEnabled = false
                returnHomeButton.isHighlighted = false
            case .idle:
                returnHomeButton.isEnabled = true
                returnHomeButton.isHighlighted = false
            case .active:
                returnHomeButton.isEnabled = true
                returnHomeButton.isHighlighted = true
            }
        } else {
            returnHomeButton.isEnabled = false
            returnHomeButton.isSelected = false
        }

    }

    private func updateGpsElements(_ gps: Gps?) {
        var fixed = false
        var labelText = ""
        if let gps = gps {
            fixed = gps.fixed
            labelText = "(\(gps.satelliteCount)) "
        }

        if fixed {
            gpsImageView.image = gpsFixedImage
        } else {
            gpsImageView.image = gpsNotFixedImage
        }

        if let location = gps?.lastKnownLocation {
            labelText += String(format: "(%.6f, %.6f, %.2f)", location.coordinate.latitude,
                location.coordinate.longitude, location.altitude)
        }
        gpsLabel.text = labelText
    }

    private func updateAltimeter(_ altimeter: Altimeter?) {
        if let altimeter = altimeter, let takeoffRelativeAltitude = altimeter.takeoffRelativeAltitude {
            altimeterView.isHidden = false
            altimeterView.set(takeOffAltitude: takeoffRelativeAltitude)
            if let groundRelativeAltitude = altimeter.groundRelativeAltitude {
                altimeterView.set(groundAltitude: groundRelativeAltitude)
            } else {
                altimeterView.set(groundAltitude: takeoffRelativeAltitude)
            }
            if let verticalSpeed = altimeter.verticalSpeed {
                verticalSpeedView.set(currentValue: verticalSpeed)
            }
        } else {
            altimeterView.isHidden = true
        }
    }

    private func updateHeading(_ compass: Compass?) {
        if let compass = compass {
            compassView.isHidden = false
            compassView.set(heading: compass.heading)
        } else {
            compassView.isHidden = true
        }
    }

    private func updateSpeedometer(_ speedometer: Speedometer?) {
        let speedStr: String
        if let speedometer = speedometer {
            let measurementInMetersPerSecond = Measurement(
                value: speedometer.groundSpeed, unit: UnitSpeed.metersPerSecond)
            speedStr = speedFormatter.string(from: measurementInMetersPerSecond)
            speedometerView.alpha = 1
        } else {
            // dim the speedometer view if there is no speedometer instrument
            speedometerView.alpha = dimInstrumentAlpha
            speedStr = ""
        }
        speedometerLabel.text = speedStr
    }

    private func updateGroundDistance() {
        let distanceStr: String
        if let droneLocation = lastDroneLocation, let userLocation = lastUserLocation {
            // compute the distance
            let distance = droneLocation.distance(from: userLocation)
            let measurementInMeters = Measurement(value: distance, unit: UnitLength.meters)
            distanceStr = distanceFormatter.string(from: measurementInMeters)
            droneDistanceView.alpha = 1
        } else {
            // dim the groundDistanceview if there is no location for the drone OR for the user
            droneDistanceView.alpha = dimInstrumentAlpha
            distanceStr = ""
        }
        droneDistanceLabel.text = distanceStr
    }

    private func updateBatteryInfo(_ batteryInfo: BatteryInfo?) {
        let batteryStr: String
        if let batteryInfo = batteryInfo {
            batteryStr = String(format: "\(batteryInfo.batteryLevel)%%")
            droneBatteryView.alpha = 1
        } else {
            // dim the batery view if there is no battery instrument
            batteryStr = ""
            droneBatteryView.alpha = dimInstrumentAlpha
        }
        droneBatteryLabel.text = batteryStr
    }

    private func updateAttitudeIndicator(_ attitudeIndicator: AttitudeIndicator?) {
        if let attitudeIndicator = attitudeIndicator {
            attitudeIndicatorView.isHidden = false
            attitudeIndicatorView.set(roll: attitudeIndicator.roll)
            attitudeIndicatorView.set(pitch: attitudeIndicator.pitch)
        } else {
            attitudeIndicatorView.isHidden = true
        }
    }

    private func listenToGamecontrollerNotifs() {
        NotificationCenter.default.addObserver(self, selector: #selector(gamepadControllerIsConnected),
            name: NSNotification.Name(rawValue: GamepadController.GamepadDidConnect), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(gamepadControllerIsDisconnected),
            name: NSNotification.Name(rawValue: GamepadController.GamepadDidDisconnect), object: nil)
    }

    private func stopListeningToGamecontrollerNotifs() {
        NotificationCenter.default.removeObserver(
            self, name: Notification.Name(rawValue: GamepadController.GamepadDidConnect), object: nil)
        NotificationCenter.default.removeObserver(
            self, name: Notification.Name(rawValue: GamepadController.GamepadDidDisconnect), object: nil)
    }
    
    /// Function called when stream view did appear.
    private func MLModelAction(){
        print("Inside the \(#function)")
        setUpMLModel()
        print("Running function: runModel()")
        //runModel(data2)
        if #available(iOS 13.0, *) {
            runModelOnStream()
        } else {
            // Fallback on earlier versions
        }
        
    }

    @objc
    private func gamepadControllerIsConnected() {
        joysticksView.isHidden = true
    }

    @objc
    private func gamepadControllerIsDisconnected() {
        joysticksView.isHidden = false
    }

    // MARK: - Facilities
    private func getFacilities() {
        refLocation = groundSdk.getFacility(Facilities.userLocation) { [weak self] userLocation in
            self?.lastUserLocation = userLocation?.location
            self?.updateGroundDistance()
        }
    }
    private func dropFacilities() {
        refLocation = nil
    }
}


extension CopterHudViewController: YuvSinkListener {
    
    func frameReady(sink: StreamSink, frame: SdkCoreFrame) {
        print("Sitesee YUVSinkListener FRAME READY")
        
        guard let metadataProtobuf = frame.metadataProtobuf else { return }
        print("Sitesee metadata Protobuf:  \(metadataProtobuf)")
        
        do {
            let decodedInfo = try CameraData(serializedData: Data(metadataProtobuf))
//            print("Sitesee YUVSink INFOPanel - decodedInfo: \(decodedInfo)") // Prints the data continously
            
            if let frameData = frame.data {
                let data2 = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: frameData), count: frame.len, deallocator: .none )
                print("Data2 is: \(data2)")
//                UIImage(data: data2)
                print("Doing the runmodel function now")
                runModel(data2: data2)
                
            }
        }
        catch {
            print("error handled in \(#function) where the data stream was accessed")
        }
        
        
        
    }
    
    func didStart(sink: StreamSink) {
        print("Sitesee Did Start YUVSinkListener")
    }
    
    func didStop(sink: StreamSink) {
        print("Sitesee Did Stop YUVSinkListener")
    }
    
    
}
