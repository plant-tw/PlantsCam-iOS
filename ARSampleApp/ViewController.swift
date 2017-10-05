//
//  ViewController.swift
//  ARSampleApp
//
//  Created by Pawel Chmiel on 13.07.2017.
//  Copyright © 2017 Droids On Roids. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
//import Photos
import MobileCoreServices

final class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet weak var resultLabel: UILabel!
    @IBOutlet weak var aimLabel: UILabel!
    @IBOutlet weak var notReadyLabel: UILabel!
    @IBOutlet var sceneView: ARSCNView!
    
    let session = ARSession()
    let vectorZero = SCNVector3()
    let sessionConfig = ARWorldTrackingConfiguration()
    var measuring = false
    var startValue = SCNVector3()
    var endValue = SCNVector3()
    var lengthInPixel : Float = 0.0
    var lengthInCentiMeter : Float = 0.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupScene()

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
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }
    
    func setupScene() {
        sceneView.delegate = self
        sceneView.session = session
        
        session.run(sessionConfig, options: [.resetTracking, .removeExistingAnchors])
        
        resetValues()
    }
    
    func resetValues() {
        measuring = false
        startValue = SCNVector3()
        endValue =  SCNVector3()
        
        updateResultLabel(0.0)
    }
    
    func updateResultLabel(_ value: Float) {
        let cm = value * 100.0
        let inch = cm*0.3937007874
        resultLabel.text = String(format: "%.2f cm / %.2f\"", cm, inch)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            self.detectObjects()
        }
    }
    
    func detectObjects() {
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
            print("pixel: \(self.lengthInPixel)")
            print("centimeter: \(self.lengthInCentiMeter)")
            print("\n")
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
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        resetValues()
        measuring = true
    }

    @objc func takePhoto() {
        // Prepare image
        let imgData = UIImageJPEGRepresentation(self.sceneView.snapshot(), 1)

        let alertController = UIAlertController(title: nil, message: "Input plant name", preferredStyle: .alert)
        alertController.addTextField { (textField) in
            textField.placeholder = "plant name"
        }
        let confirmAction = UIAlertAction(title: "Confirm", style: .default) { (alertAction) in

            // Prepare metadata
            let plantName = alertController.textFields?.first?.text ?? ""
            let exifUserComment = ExifUserComment(lengthInPixel: self.lengthInPixel, lengthInCentiMeter: self.lengthInCentiMeter, plantName: plantName)
            // Create a String from the data
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
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        measuring = false
    }
    
    func randomStringWithLength(len: NSInteger) -> String {
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
