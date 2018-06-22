//
//  ViewController.swift
//  ARSampleApp
//
//  Created by Pawel Chmiel on 13.07.2017.
//  Copyright © 2017 Droids On Roids. All rights reserved.
//

import UIKit
import ARKit
import SceneKit
import Vision

import MobileCoreServices
import CoreMotion
import CoreLocation

final class ViewController: UIViewController {

    @IBOutlet weak var resultLabel: UILabel!
    @IBOutlet weak var aimLabel: UILabel!
    @IBOutlet weak var notReadyLabel: UILabel!
    @IBOutlet var sceneView: ARSCNView!
    
    private let session = ARSession()
    private let vectorZero = SCNVector3()
    private let sessionConfig = ARWorldTrackingConfiguration()
    private var isMeasuring = false

    private var lengthInPixel : Float? = nil
    private var lengthInCentiMeter : Float? = nil

    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()

    private let cameraButton = UIButton(type: .custom)
    private var photos : [Data] = [Data]()
    private var exifs : [ExifUserComment] = [ExifUserComment]()
    private var recordTimer : Timer? = nil {
        willSet {
            if newValue == nil {
                cameraButton.alpha = 1.0
            } else {
                cameraButton.alpha = 0.3
            }
        }
    }

    // Vision classification request and model
    /// - Tag: ClassificationRequest
    private lazy var classificationRequest: VNCoreMLRequest = {
        do {
            // Instantiate the model from its generated Swift class.
            let model = try VNCoreMLModel(for: Plant().model)
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                self?.processClassifications(for: request, error: error)
            })

            // Crop input images to square area at center, matching the way the ML model was trained.
            request.imageCropAndScaleOption = .centerCrop

            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    // The pixel buffer being held for analysis; used to serialize Vision requests.
    private var currentBuffer: CVPixelBuffer?
    private let labels = ["三色堇", "久留米杜鵑", "九重葛", "五爪金龍", "仙丹花", "四季秋海棠", "垂花懸鈴花", "大花咸豐草", "天竺葵", "射干", "平戶杜鵑", "木棉", "木茼蒿", "杜鵑花仙子", "烏來杜鵑", "玫瑰", "白晶菊", "皋月杜鵑", "矮牽牛", "石竹", "紫嬌花", "羊蹄甲", "美人蕉", "艾氏香茶菜", "萬壽菊", "著生杜鵑", "蔓花生", "蛇苺", "蛇莓", "蜀葵", "蟛蜞菊", "通泉草", "酢漿草", "野菊花", "金毛杜鵑", "金盞花", "金絲桃", "金雞菊", "金魚草", "銀葉菊", "鳳仙花", "黃秋英", "黃金菊", "龍船花"]


    // MARK: - View Controller Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup scene
        sceneView.delegate = self
        sceneView.session = session
        session.delegate = self
        session.run(sessionConfig, options: [.resetTracking, .removeExistingAnchors])
        resetValues()

        // Camera button
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(cameraButton)
        NSLayoutConstraint.activate([
            cameraButton.bottomAnchor.constraint(equalTo: self.sceneView.bottomAnchor, constant: -10.0),
            cameraButton.centerXAnchor.constraint(equalTo: self.sceneView.centerXAnchor),
            cameraButton.widthAnchor.constraint(equalToConstant: 160.0),
            cameraButton.heightAnchor.constraint(equalToConstant: 160.0)
            ])
        cameraButton.setImage(UIImage(named: "circle-160"), for: .normal)
        cameraButton.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)

        // Device motion manager
        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical)

        NotificationCenter.default.addObserver(self,
            selector: #selector(applicationDidBecomeActive(notification:)),
            name: NSNotification.Name.UIApplicationDidBecomeActive,
            object: nil)

        // Location permission
        switch CLLocationManager.authorizationStatus() {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            let alert = UIAlertController.ptw_alert(with: "Without location information, prediction might be inaccurate, and data collecting will be disabled (You can change settings later).")
            present(alert, animated: true, completion: nil)
        default:
            break
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }

    @objc func applicationDidBecomeActive(notification: NSNotification) {
        resultLabel.text = ""
    }

    // MARK: - Button action

    @objc private func takePhoto() {
        if recordTimer == nil {
            recordTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] (timer) in
                guard let weakSelf = self,
                    let imgData = UIImageJPEGRepresentation(weakSelf.sceneView.snapshot(), 1),
                    let lengthInPixel = weakSelf.lengthInPixel,
                    let lengthInCentiMeter = weakSelf.lengthInCentiMeter,
                    let roll = weakSelf.motionManager.deviceMotion?.attitude.roll,
                    let pitch = weakSelf.motionManager.deviceMotion?.attitude.pitch,
                    let yaw = weakSelf.motionManager.deviceMotion?.attitude.yaw else {
                        self?.recordTimer?.invalidate()
                        self?.recordTimer = nil
                        let alert = UIAlertController.ptw_alert(with: "sensor data not ready")
                        self?.present(alert, animated: true, completion: nil)
                        return
                }
                guard let userLocation = weakSelf.locationManager.location else {
                    let alert = UIAlertController(title: "Location is disabled", message: "We need location information to collect better data.", preferredStyle: .alert)
                    let changeSetting = UIAlertAction(title: "Change settings", style: .default, handler: { (action) in
                        guard let url = URL(string: UIApplicationOpenSettingsURLString) else { return }
                        UIApplication.shared.open(url, completionHandler: nil)
                    })
                    let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
                    alert.addAction(changeSetting)
                    alert.addAction(cancel)
                    weakSelf.present(alert, animated: true, completion: nil)
                    // Stop the timer
                    weakSelf.recordTimer?.invalidate()
                    weakSelf.recordTimer = nil
                    return
                }
                let exifUserComment = ExifUserComment(lengthInPixel: lengthInPixel,
                                                      lengthInCentiMeter: lengthInCentiMeter,
                                                      roll: roll,
                                                      pitch: pitch,
                                                      yaw: yaw,
                                                      latitude: userLocation.coordinate.latitude,
                                                      longitude: userLocation.coordinate.longitude)
                weakSelf.exifs.append(exifUserComment)
                weakSelf.photos.append(imgData)
            })
        } else {
            // Stop the timer
            recordTimer?.invalidate()
            recordTimer = nil

            // Early check
            if photos.count != exifs.count {
                let alert = UIAlertController.ptw_alert(with: "photos and exifs count not consistent")
                present(alert, animated: true, completion: nil)
                return
            }

            // Prepare a directory to save in
            let currentTime = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "hhmm"
            let timeStr = dateFormatter.string(from: currentTime)
            let randomStr = randomStringWithLength(len: 5)
            let directoryName = timeStr + randomStr
            let docDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
            let directoryURLString = docDir.appending("/" + directoryName)
            if !FileManager.default.fileExists(atPath: directoryURLString) {
                do {
                    try FileManager.default.createDirectory(atPath: directoryURLString, withIntermediateDirectories: false, attributes: nil)
                } catch (let error) {
                    let alert = UIAlertController.ptw_alert(with: error.localizedDescription)
                    present(alert, animated: true, completion: nil)
                    return
                }
            } else {
                let alert = UIAlertController.ptw_alert(with: "Random collision! Try again.")
                present(alert, animated: true, completion: nil)
                return
            }

            // Save images with exif
            let jsonEncoder = JSONEncoder()
            for (index, imgData) in photos.enumerated() {
                // Create a JSON String of the sensor data
                var exifUserCommentString = ""
                if let jsonData = try? jsonEncoder.encode(exifs[index]),
                    let jsonString = String(data: jsonData, encoding: .utf8) {
                    exifUserCommentString = jsonString
                }
                let latitudeRef = exifs[index].latitude < 0.0 ? "S" : "N"
                let longitudeRef = exifs[index].longitude < 0.0 ? "W" : "E"
                let gpsDict = [kCGImagePropertyGPSLatitude: abs(exifs[index].latitude),
                               kCGImagePropertyGPSLatitudeRef: latitudeRef,
                               kCGImagePropertyGPSLongitude: abs(exifs[index].longitude),
                               kCGImagePropertyGPSLongitudeRef: longitudeRef] as CFDictionary
                let exif = [kCGImagePropertyExifUserComment: exifUserCommentString] as CFDictionary
                let metadata = [kCGImagePropertyExifDictionary: exif,
                                kCGImagePropertyGPSDictionary: gpsDict]

                // Save images as files in the directory
                let fileURLString = directoryURLString + "/" + "\(directoryName)_\(index).jpg"
                let pathURL = URL(fileURLWithPath: fileURLString)
                guard let destination = CGImageDestinationCreateWithURL(pathURL as CFURL, kUTTypeJPEG, 1, nil),
                    let source = CGImageSourceCreateWithData(imgData as CFData, nil) else {
                        let alert = UIAlertController.ptw_alert(with: "Error occurs when preparing destination or source")
                        present(alert, animated: true, completion: nil)
                        return
                }
                CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
                CGImageDestinationFinalize(destination)
            }
            // Ending and removing
            photos.removeAll()
            exifs.removeAll()
        }
    }

    private func randomStringWithLength(len: NSInteger) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        var str = ""
        for _ in 1...len {
            let cidx = Int(arc4random_uniform(UInt32(letters.count)))
            let charIndex = letters.index(letters.startIndex, offsetBy: cidx)
            str.append(letters[charIndex])
        }
        return str
    }
}

// MARK: - Touch and hold to measure length

extension ViewController {

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        resetValues()
        isMeasuring = true
        aimLabel.backgroundColor = UIColor.red.withAlphaComponent(0.3)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isMeasuring = false
        aimLabel.backgroundColor = UIColor.clear
    }

    private func resetValues() {
        isMeasuring = false
        resultLabel.text = ""
    }

    private func updateResultLabel() {
        if let cm = lengthInCentiMeter, let px = lengthInPixel {
            resultLabel.text = String(format: "%.1f cm / %.0f px", cm, px)
        }
    }
}

// MARK: - ARSCNViewDelegate

extension ViewController : ARSCNViewDelegate {

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            self.detectObjects()
        }
    }

    private func detectObjects() {
        // Calculating pixel
        let startFrameValue = CGPoint(x: view.center.x - 50, y: view.center.y)
        let endFrameValue = CGPoint(x: view.center.x + 50, y: view.center.y)
        let deltaX = Float(endFrameValue.x - startFrameValue.x)
        let deltaY = Float(endFrameValue.y - startFrameValue.y)
        let lengthInPoint = sqrtf(deltaX * deltaX + deltaY * deltaY)          // in point
        let lengthInPixel = lengthInPoint * Float(UIScreen.main.scale)        // in pixel

        // Calculating length
        if let startWorldVector = sceneView.realWorldVector(screenPos: startFrameValue),
            let endWorldVector = sceneView.realWorldVector(screenPos: endFrameValue) {
            // Show aimLabel
            aimLabel.isHidden = false
            notReadyLabel.isHidden = true
            // Prepare scale
            let lengthInMeter = startWorldVector.distance(from: endWorldVector)
            self.lengthInPixel = lengthInPixel
            self.lengthInCentiMeter = lengthInMeter * 100
            // Show scale if isMeasuring
            if isMeasuring {
                updateResultLabel()
            }
        }
    }
}

// MARK: - ARSessionDelegate

extension ViewController : ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Do not enqueue other buffers for processing while another Vision task is still running.
        // The camera stream has only a finite amount of buffers available; holding too many buffers for analysis would starve the camera.
        guard currentBuffer == nil else {
            return
        }
        // Uncomment code below when we're doing inference with AR information
        /*
        guard case .normal = frame.camera.trackingState else {
            return
        }
         */

        // Retain the image buffer for Vision processing.
        self.currentBuffer = frame.capturedImage
        classifyCurrentImage()
    }

    // Run the Vision+ML classifier on the current image buffer.
    /// - Tag: ClassifyCurrentImage
    private func classifyCurrentImage() {
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!)
        DispatchQueue(label: "com.nandalu.PlantsCam.serialVisionQueue").async {
            do {
                // Release the pixel buffer when done, allowing the next buffer to be processed.
                defer { self.currentBuffer = nil }
                try requestHandler.perform([self.classificationRequest])
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }

    // Handle completion of the Vision request and choose results to display.
    /// - Tag: ProcessClassifications
    private func processClassifications(for request: VNRequest, error: Error?) {
        if isMeasuring {
            return
        }
        guard let results = request.results,
            let classifications = results as? [VNCoreMLFeatureValueObservation] else {
                print("Unable to classify image.\n\(error!.localizedDescription)")
                return
        }

        // Show a label for the highest-confidence result (but only above a minimum confidence threshold).
        if let bestResult = classifications.first(where: { result in result.confidence > 0.5 }),
            // From: https://gist.github.com/otmb/7adf88882d2995ca63ad0ee5a0d3f91a
            let featureArray = bestResult.featureValue.multiArrayValue {
            let length = featureArray.count
            let doublePtr = featureArray.dataPointer.bindMemory(to: Double.self, capacity: length)
            let doubleBuffer = UnsafeBufferPointer(start: doublePtr, count: length)
            let output = Array(doubleBuffer)
            if let maxElement = output.max(),
                let maxIndex = output.index(of: maxElement) {
                if maxIndex < labels.count {
                    let bestLabelElement = labels[maxIndex]
                    DispatchQueue.main.async {
                        self.resultLabel.text = String(format: "%@ (%.2f)", bestLabelElement, maxElement)
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.resultLabel.text = ""
            }
        }
    }
}
