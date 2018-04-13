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

import MobileCoreServices
import CoreMotion

final class ViewController: UIViewController {

    @IBOutlet weak var resultLabel: UILabel!
    @IBOutlet weak var aimLabel: UILabel!
    @IBOutlet weak var notReadyLabel: UILabel!
    @IBOutlet var sceneView: ARSCNView!
    
    private let session = ARSession()
    private let vectorZero = SCNVector3()
    private let sessionConfig = ARWorldTrackingConfiguration()
    private var measuring = false
    private var startValue = SCNVector3()
    private var endValue = SCNVector3()

    private var lengthInPixel : Float? = nil
    private var lengthInCentiMeter : Float? = nil

    private let motionManager = CMMotionManager()

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

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup scene
        sceneView.delegate = self
        sceneView.session = session
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
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }

    // MARK: - Button action

    @objc private func takePhoto() {
        if recordTimer == nil {
            recordTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true, block: { [weak self] (timer) in
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
                let exifUserComment = ExifUserComment(lengthInPixel: lengthInPixel,
                                                      lengthInCentiMeter: lengthInCentiMeter,
                                                      roll: roll,
                                                      pitch: pitch,
                                                      yaw: yaw)
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
                let exif = [kCGImagePropertyExifUserComment: exifUserCommentString]
                let metadata = [kCGImagePropertyExifDictionary: exif as CFDictionary]

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
        measuring = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        measuring = false
    }

    private func resetValues() {
        measuring = false
        startValue = SCNVector3()
        endValue =  SCNVector3()
        updateResultLabel(0.0)
    }

    private func updateResultLabel(_ value: Float) {
        let cm = value * 100.0
        let inch = cm * 0.3937007874
        resultLabel.text = String(format: "%.2f cm / %.2f\"", cm, inch)
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
        let startFrameValue = view.center
        let endFrameValue = CGPoint(x: view.center.x + 100, y: view.center.y)
        let deltaX = Float(endFrameValue.x - startFrameValue.x)
        let deltaY = Float(endFrameValue.y - startFrameValue.y)
        let lengthInPoint = sqrtf(deltaX * deltaX + deltaY * deltaY)          // in point
        let lengthInPixel = lengthInPoint * Float(UIScreen.main.scale)        // in pixel

        // Calculating length
        if let startWorldVector = sceneView.realWorldVector(screenPos: startFrameValue),
            let endWorldVector = sceneView.realWorldVector(screenPos: endFrameValue) {
            let lengthInMeter = startWorldVector.distance(from: endWorldVector)
            self.lengthInPixel = lengthInPixel
            self.lengthInCentiMeter = lengthInMeter * 100
        }
        if let worldPos = sceneView.realWorldVector(screenPos: view.center) {
            aimLabel.isHidden = false
            notReadyLabel.isHidden = true
            if measuring {
                if startValue == vectorZero {
                    startValue = worldPos
                }
                endValue = worldPos
                updateResultLabel(startValue.distance(from: endValue))
            }
        }
    }
}
