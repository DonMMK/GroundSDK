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

    var frameCounter: Int = 0
    var isProcessingFrame: Bool = false
    
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
            cameraLive = streamServer.value?.live(source: .frontCamera) { stream in
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

    
    func setUpURLPath() -> String? {
        
        // Accessing the document directory for the GroundSDK
        let documentDirectory = FileManager.SearchPathDirectory.documentDirectory

        let userDomainMask = FileManager.SearchPathDomainMask.userDomainMask
        let paths = NSSearchPathForDirectoriesInDomains(documentDirectory, userDomainMask, true)
        return paths.first
    }
    
    
    func createImageFromImage(imageName: String) -> UIImage? {
        let URLpath = setUpURLPath()
        
        if let URLpath = URLpath {
            let imageUrl = URL(fileURLWithPath: URLpath).appendingPathComponent(imageName)

            guard let newimage = UIImage(contentsOfFile: imageUrl.path) else {print("Sitesee No Image"); return nil }
            print("Sitesee Image From File: \(imageName) , Size: \(newimage.size)")
            let imageData = newimage.jpegData(compressionQuality: 1)
            
            return newimage
        }
        else { return nil }
        
    }
        
    func createImageFromData(data2: Data, save: Bool, saveImageName: String) -> UIImage? {

//            guard let newImage = resize_image(image: image, resize_target: 640) else { print("Sitesee No Resize Image"); return (nil, dirPath )}
//            print("Sitesee: NewResize Image: \(newImage.size)")
        
        print("DataInput: \(data2)")
        
        let cgProvider = CGDataProvider(data: data2 as CFData)

        let im: CGImage = CGImage(
          width: 640,
          height: 640,
          bitsPerComponent: 8,
          bitsPerPixel: 32,
          bytesPerRow: 640 * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue),
          provider: cgProvider!,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
        )!
        
        print("\(im.width), \(im.height)")
        
        let newimage = UIImage(cgImage: im)
        
        print("!!! Check !!!! New Data image size is: \(newimage.size)")
        
        if save == true, let pngData = newimage.pngData() {
            let URLPath = setUpURLPath()
            if let dirPath = URLPath {
               let path = URL(fileURLWithPath: dirPath).appendingPathComponent(saveImageName)
                try? pngData.write(to: path)
                print("Saved the image: \(saveImageName)")
            }
        }
        
        return newimage
    }
    
    
    func runMLModel(image: UIImage?) {
        print("Sitesee Run Model")
        guard let newimage = image else { print("Sitesee No Image Provided"); return }

        /// TO DO; find a better solution to do the handler and request for images/ multiple images , make the reuqest a general one.
        let handler = VNImageRequestHandler(cgImage: (newimage.cgImage!))
        let request = VNCoreMLRequest(model: selectedVNModel!) { (request, error) in
                    print("Sitesee runMLModel Request: \(request)")
                    print("Sitesee runMLModel Error: \(error)")
        }
        
        request.imageCropAndScaleOption = .scaleFill
        do {
            try handler.perform([request])
            
            let observation = request.results?.first
            let observation2 = observation as? VNDetectedObjectObservation
            
            //print("Sitesee ML Results: \(observation2?.labels[0].identifier)")
            print("Sitesee ML bb: \(observation2!.boundingBox)")
            print("Sitesee ML bb minx: \(observation2!.boundingBox.minX) bb max y: \(1 - (observation2!.boundingBox.maxY)) ")
            print("Sitesee ML bb width: \(observation2!.boundingBox.width) bb height: \(observation2!.boundingBox.height) ")
            print("Sitesee ML bb origin: \(observation2!.boundingBox.origin) bb size: \(observation2!.boundingBox.size) ")
            
            // Use as center of the bounding box
            print("Sitesee ML bb minx + width \(observation2!.boundingBox.minX + observation2!.boundingBox.width / 2)  bb min y + height: \(-1 * observation2!.boundingBox.minY - observation2!.boundingBox.height / 2 ) ")
            
            print("Sitesee ML confidence: \(observation2!.confidence)")
            
            // use as height and width
            let flippedBox = CGRect(x: observation2!.boundingBox.minX, y: 1 - observation2!.boundingBox.maxY, width: observation2!.boundingBox.width, height: observation2!.boundingBox.height)
            let box = VNImageRectForNormalizedRect(flippedBox, Int(newimage.cgImage!.width), Int(newimage.cgImage!.height))
            print("SiteSee ML flippedbox: \(flippedBox) , box: \(box)")
//            let y = observation2?.boundingBox
//            y[:, 0] = (observation2?.boundingBox[:, 0] + observation2?.boundingBox[:, 2]) / 2  // x center
//                y[:, 1] = (observation2?.boundingBox[:, 1] + observation2?.boundingBox[:, 3]) / 2  // y center
//                y[:, 2] = observation2?.boundingBox[:, 2] - observation2?.boundingBox[:, 0]  // width
//                y[:, 3] = observation2?.boundingBox[:, 3] - observation2?.boundingBox[:, 1]  // height
            
            
        } catch {
            print(error)
        }
            
    }

    
    
//    @available(iOS 13.0, *)
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
    func createImageClassifier() -> VNCoreMLModel {
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
    
    
    func calculateNewResolution(target_width: Double, target_height: Double, original_width: Double, original_height: Double) -> (w: Double, h: Double) {
        
        // This assumes the width is always larger
        let aspectRatio = original_width / original_height
        let new_width = target_width
        let new_height = target_height / aspectRatio

        let w = round(new_width) // selft explanatory function, right!
        let h = round(new_height) // adjust the rounded width with height

        return (w, h)
    }
    
    
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
    
    func valueClip(inputValue: Double) -> Double {
        let clipValue: Double
        if 0...255 ~= inputValue {
            clipValue = inputValue
        } else {
            clipValue = (inputValue < 0) ? 0 : 255
        }
        
        return clipValue
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
//        print("Running function: runModel()")
        //runModel(data2)
        if #available(iOS 13.0, *) {
//            runModelOnStream()
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
        frameCounter = frameCounter + 1
        if frameCounter % 1 == 0 , self.isProcessingFrame == false {
        do {
            guard let metadataProtobuf = frame.metadataProtobuf, let frameData = frame.data else { return }
            print("Sitesee metadata Protobuf:  \(metadataProtobuf)")
        
        
            let decodedInfo = try CameraData(serializedData: metadataProtobuf)
//            print("Sitesee YUVSink INFOPanel - decodedInfo: \(decodedInfo)") // Prints the data continously
            
            self.isProcessingFrame = true
            DispatchQueue.global(qos: .utility).async {
                let imageSize = 1280 * 720
                let dataSize = frame.len

                let data2 = Data(bytes: frameData, count: dataSize)
                
                // start j
                var RGBout = Data(count: 640*4*640*4)
                let UOffset = imageSize
                let VOffset = imageSize + 1
                let numRows = 360
                let numCols = 640
                let side = (numCols - numRows) / 2
                let startOne = DispatchTime.now()
                
                var step = 0
                var stepUV = 0
                var rgbOff = side * 640 * 4
                // Loop takes 0.51-0.55 seconds
                for row in 0..<numRows {
                    for col in 0..<numCols {
//                        let step = row * 2 * numCols * 2 + col * 2
//                        let stepUV = row * 2 * numCols + col * 2
                        let y = Int32(data2[step])
                        let u = Int32(data2[UOffset + stepUV])
                        let v = Int32(data2[VOffset + stepUV])
                        step += 2
                        stepUV += 2
                        // got carried away and made these bitshifts instead of division.
                        let Rvalue = y + ((5743 * (v - 128)) >> 12)
                        let Gvalue = y - ((1409 * (u-128)) >> 12) - ((2925 * (v-128)) >> 12)
                        let Bvalue = y + ((7258 * (u-128)) >> 12)
                        
//                        let rgbOff = ((row + side) * 640 + col) * 4
                        rgbOff += 1
                        RGBout[rgbOff] = Rvalue > 255 ? 255 : (Rvalue < 0 ? 0 : UInt8(Rvalue))
                        rgbOff += 1
                        RGBout[rgbOff] = Gvalue > 255 ? 255 : (Gvalue < 0 ? 0 : UInt8(Gvalue))
                        rgbOff += 1
                        RGBout[rgbOff] = Bvalue > 255 ? 255 : (Bvalue < 0 ? 0 : UInt8(Bvalue))
                        rgbOff += 1
                    }
                    step += numCols * 2
                    rgbOff += (640 - numCols) * 4
                }
                let endOne = DispatchTime.now()
                
                
                // end j
                    
//                var Y_data: [Double] = []
//                var U_data: [Double] = []
//                var V_data: [Double] = []
//
////                    var Y_data: [Double] = Array(repeating: 0, count: imageSize)
////                    var U_data: [Double] = Array(repeating: 0, count: imageSize)
////                    var V_data: [Double] = Array(repeating: 0, count: imageSize)
//
////                var UV_Iter = UV.makeIterator()
////                var count_step = 0
////                var count_row = 0
////
////                for ii in 0..<Int(imageSize/2) {
////
////                    count_step = ii * 2
////                    count_row = ((ii*2) + 1) + 1280
////
////                    let U_value = UV_Iter.next()!
////                    let V_value = UV_Iter.next()!
////
//////                    count_step = ii * 1280
//////                    Y_data.insert(Double(Y_value), at: ii)
////                    U_data.insert(Double(U_value), at: count_step)
////                    U_data.insert(Double(U_value), at: count_step+1)
////
////                    U_data.insert(Double(U_value), at: count_row)
////                    U_data.insert(Double(U_value), at: count_row+1)
////
////                    V_data.insert(Double(V_value), at: count_step)
////                    V_data.insert(Double(V_value), at: count_step+1)
////
////                    V_data.insert(Double(V_value), at: count_row)
////                    V_data.insert(Double(V_value), at: count_row+1)
////                }
//
//                Y.forEach() { value in
//                    Y_data.append(Double(value))
//                }
//
//                    UV.enumerated().forEach() { (index, value) in
//                        if index % 2 == 0 {
//                            U_data.append(Double(value))
//                            U_data.append(Double(value))
//                        }
//                        else {
//                            V_data.append(Double(value))
//                            V_data.append(Double(value))
//                        }
//                    }
//
//                    let temp_U_data = U_data
//                    let temp_V_data = V_data
//
//                    for ii in 0..<360 {
//                        let step = ii * 1280
//                        let rowStep = step + ii*1280
//                        let U_rowData = temp_U_data[step..<(step+1280)]
//                        U_data.insert(contentsOf: U_rowData, at: rowStep)
//
//                        let V_rowData = temp_V_data[step..<(step+1280)]
//                        V_data.insert(contentsOf: V_rowData, at: rowStep)
//
//                    }
//
//                let filterY_Data = Y_data.enumerated().filter(){ $0.offset % 2 == 0 }
//                let filterU_Data = U_data.enumerated().filter(){ $0.offset % 2 == 0 }
//                let filterV_Data = V_data.enumerated().filter(){ $0.offset % 2 == 0 }
//
//
//                print("Y Filter \(filterY_Data.count), Y: \(Y_data.count), U: \(U_data.count), V: \(V_data.count)")
//
//                let startRGBStuff = DispatchTime.now()
//                    var RGBData: Data = Data(count: RGBimageSize)
//                    rgbInd = 0
//
//                    for ii in (0..<(1280 * 720)) {
//                        let Rvalue = Y_data[ii] + (1.402 * (V_data[ii] - 128))
//                        let Gvalue = Y_data[ii] - (0.344 * (U_data[ii]-128)) - (0.714 * (V_data[ii]-128))
//                        let Bvalue = Y_data[ii] + (1.772 * (U_data[ii]-128))
//
//                        let RClipValue: UInt8 = Rvalue > 255 ? 255 : (Rvalue < 0 ? 0 : UInt8(Rvalue))
//                        let GClipValue: UInt8 = Gvalue > 255 ? 255 : (Gvalue < 0 ? 0 : UInt8(Gvalue))
//                        let BClipValue: UInt8 = Bvalue > 255 ? 255 : (Bvalue < 0 ? 0 : UInt8(Bvalue))
//
//
//                        RGBData[rgbInd] = 0
//                        rgbInd += 1
//                        RGBData[rgbInd] = UInt8(RClipValue)
//                        rgbInd += 1
//                        RGBData[rgbInd] = UInt8(GClipValue)
//                        rgbInd += 1
//                        RGBData[4*ii + 3] = UInt8(BClipValue)
//                        rgbInd += 1
//
//                    }
//
//                let endRGBStuff = DispatchTime.now()
//                print("Timer: YUV Stuff Run Time \(Double(startRGBStuff.uptimeNanoseconds - startThreadTime.uptimeNanoseconds) / 1_000_000_000)")
//                print("Timer: RGB Stuff Run Time \(Double(endRGBStuff.uptimeNanoseconds - startRGBStuff.uptimeNanoseconds) / 1_000_000_000)")
                print("Timer: One Stuff Run Time \(Double(endOne.uptimeNanoseconds - startOne.uptimeNanoseconds) / 1_000_000_000)")
                
                    print("Convert to Image from Frame")
//                let startGetImageData = DispatchTime.now()
                  //  let frameimage = self.createImageFromData(data2: RGBout, save: true, saveImageName: "SaveImage4.png")
//                let endGetImageData = DispatchTime.now()
//                print("Timer: createImageFromData Run Time \(Double(endGetImageData.uptimeNanoseconds - startGetImageData.uptimeNanoseconds) / 1_000_000_000)")
                
                let frameimage = self.createImageFromImage(imageName: "SaveImagev4.PNG")
                    print("Doing the runMLmodel function now")
                self.runMLModel(image: frameimage)
                
                print("End FrameReady")
                self.isProcessingFrame = false
//                let endTime = DispatchTime.now()
//                print("Timer: Dispatch Run Time \(Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000)")
            }
        }
        catch { print("error handled in \(#function) where the data stream was accessed") }
        }
    }
    
    func didStart(sink: StreamSink) {
        print("Sitesee Did Start YUVSinkListener")
    }
    
    func didStop(sink: StreamSink) {
        print("Sitesee Did Stop YUVSinkListener")
    }
    
    
}
