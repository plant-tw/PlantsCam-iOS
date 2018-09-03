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

    private let cameraViewFactory = CameraViewFactory()
    private var sceneView: SCNView!

    private var lengthInPixel : Float? = nil
    private var lengthInCentiMeter : Float? = nil

    private lazy var aiVision : AIVision = {
        let ai = AIVision(inferences: { (inference) in
            if !self.cameraViewFactory.shouldShowScale {
                self.title = inference
            }
        })
        return ai
    }()

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

    // MARK: - View Controller Life Cycle

    override func loadView() {
        // TODO: check ARWorldTrackingConfiguration.isSupported and provide fallback
        let cameraView = cameraViewFactory.arView(didUpdateFrame: { (capturedPixelBuffer) in
            // Do not enqueue other buffers for processing while another Vision task is still running.
            // The camera stream has only a finite amount of buffers available; holding too many buffers for analysis would starve the camera.
            guard self.aiVision.currentBuffer == nil else {
                return
            }
            self.aiVision.currentBuffer = capturedPixelBuffer
        }, didUpdateScale: {(lengthInPixel, lengthInCentiMeter) in
            self.lengthInPixel = lengthInPixel
            self.lengthInCentiMeter = lengthInCentiMeter
            if self.cameraViewFactory.shouldShowScale {
                self.title = String(format: "%.1f cm / %.0f px", lengthInCentiMeter, lengthInPixel)
            }
        })
        sceneView = cameraView
        view = cameraView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

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
        cameraViewFactory.arSession?.pause()
    }

    @objc func applicationDidBecomeActive(notification: NSNotification) {
        self.title = ""
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
        cameraViewFactory.shouldShowScale = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cameraViewFactory.shouldShowScale = false
    }

    private func resetValues() {
        cameraViewFactory.shouldShowScale = false
        title = ""
    }
}
