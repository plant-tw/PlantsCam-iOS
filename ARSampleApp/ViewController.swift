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
        UIImageWriteToSavedPhotosAlbum(sceneView.snapshot(), nil, nil, nil)

        let exif = [kCGImagePropertyExifUserComment: "{\"lengthInPixel\": \(self.lengthInPixel), \"lengthInCentiMeter\": \(self.lengthInCentiMeter)}"]
        let metadata = [kCGImagePropertyExifDictionary: exif as CFDictionary]

        let imgData = UIImageJPEGRepresentation(sceneView.snapshot(), 1)
        let source = CGImageSourceCreateWithData(imgData! as CFData, nil)
        let docDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let tmpURLString = docDir.appending("/qq.jpg")
        let tmpURL = URL(fileURLWithPath: tmpURLString)
        let destination = CGImageDestinationCreateWithURL(tmpURL as CFURL, kUTTypeJPEG, 1, nil)
        CGImageDestinationAddImageFromSource(destination!, source!, 0, metadata as CFDictionary)
        CGImageDestinationFinalize(destination!)
//        CFRelease(source!)
//        CFRelease(destination!)
//        PHPhotoLibrary.shared().performChanges({
//            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tmpURL)
//        }) { (success, error) in
//            print(success)
//        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        measuring = false
    }
    
}
