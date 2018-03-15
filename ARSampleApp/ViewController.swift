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

    // MARK: - View Controller Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup scene
        sceneView.delegate = self
        sceneView.session = session
        session.run(sessionConfig, options: [.resetTracking, .removeExistingAnchors])
        resetValues()

        // Camera button
        let cameraButton = UIButton(type: .custom)
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
        // Prepare image
        let imgData = UIImageJPEGRepresentation(self.sceneView.snapshot(), 1)
        // Input plant name
        let alertController = UIAlertController(title: nil, message: "Input plant name", preferredStyle: .alert)
        alertController.addTextField { (textField) in
            textField.placeholder = "plant name"
        }
        let confirmAction = UIAlertAction(title: "Confirm", style: .default) { (alertAction) in
            // Prepare sensor data
            guard let lengthInPixel = self.lengthInPixel,
                let lengthInCentiMeter = self.lengthInCentiMeter,
                let roll = self.motionManager.deviceMotion?.attitude.roll,
                let pitch = self.motionManager.deviceMotion?.attitude.pitch,
                let yaw = self.motionManager.deviceMotion?.attitude.yaw else {
                    let alertController = UIAlertController(title: nil, message: "sensor data not ready", preferredStyle: .alert)
                    let confirmAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                    alertController.addAction(confirmAction)
                    self.present(alertController, animated: true, completion: nil)
                    return
            }
            let plantName = alertController.textFields?.first?.text ?? ""
            let exifUserComment = ExifUserComment(lengthInPixel: lengthInPixel,
                                                  lengthInCentiMeter: lengthInCentiMeter,
                                                  roll: roll,
                                                  pitch: pitch,
                                                  yaw: yaw,
                                                  plantName: plantName)
            // Create a JSON String of the sensor data
            let jsonEncoder = JSONEncoder()
            var exifUserCommentString = ""
            if let jsonData = try? jsonEncoder.encode(exifUserComment),
                let jsonString = String(data: jsonData, encoding: .utf8) {
                exifUserCommentString = jsonString
            }
            let exif = [kCGImagePropertyExifUserComment: exifUserCommentString]
            let metadata = [kCGImagePropertyExifDictionary: exif as CFDictionary]

            // Prepare file name to save
            let docDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
            let randomStr = self.randomStringWithLength(len: 8)
            let tmpURLString = docDir.appending("/"+randomStr+".jpg")

            // Save image to file
            let tmpURL = URL(fileURLWithPath: tmpURLString)
            let destination = CGImageDestinationCreateWithURL(tmpURL as CFURL, kUTTypeJPEG, 1, nil)
            let source = CGImageSourceCreateWithData(imgData! as CFData, nil)
            CGImageDestinationAddImageFromSource(destination!, source!, 0, metadata as CFDictionary)
            CGImageDestinationFinalize(destination!)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(confirmAction)
        alertController.addAction(cancelAction)
        self.present(alertController, animated: true, completion: nil)
    }

    private func randomStringWithLength(len: NSInteger) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var str = ""
        for _ in 0...len {
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
