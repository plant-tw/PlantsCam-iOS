//
//  CameraViewFactory.swift
//  ARSampleApp
//
//  MIT License
//  Copyright (c) 2018 Denken Chen, Apple Inc., Droids On Roids LLC
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import UIKit
import ARKit

final class CameraViewFactory : NSObject {

    var shouldShowScale = false {
        didSet {
            if shouldShowScale {
                scaleLabel?.backgroundColor = UIColor.red.withAlphaComponent(0.3)
                sceneView.showsStatistics = true
                sceneView.debugOptions = [SCNDebugOptions.showFeaturePoints]
            } else {
                scaleLabel?.backgroundColor = .clear
                sceneView.showsStatistics = false
                sceneView.debugOptions = []
            }
        }
    }
    private var arSession : ARSession? = nil
    private lazy var sceneView : ARSCNView = {
        return ARSCNView()
    }()
    private var scaleLabel : UILabel? = nil
    private let scaleWidth : CGFloat = 100.0
    private var didUpdateFrame: ((_ pixelBuffer: CVPixelBuffer) -> Void)? = nil
    private var didUpdateScale: ((_ lengthInPixel: Float, _ lengthInCentiMeter: Float) -> Void)? = nil

    func arView(didUpdateFrame: @escaping (_ pixelBuffer: CVPixelBuffer) -> Void,
                didUpdateScale: @escaping (_ lengthInPixel: Float, _ lengthInCentiMeter: Float) -> Void) -> ARSCNView {
        self.didUpdateFrame = didUpdateFrame
        self.didUpdateScale = didUpdateScale

        let scaleLabel = UILabel()
        scaleLabel.translatesAutoresizingMaskIntoConstraints = false
        sceneView.addSubview(scaleLabel)
        NSLayoutConstraint.activate([
            scaleLabel.centerXAnchor.constraint(equalTo: sceneView.centerXAnchor),
            scaleLabel.centerYAnchor.constraint(equalTo: sceneView.centerYAnchor),
            scaleLabel.widthAnchor.constraint(equalToConstant: scaleWidth),
            scaleLabel.heightAnchor.constraint(equalToConstant: 20.0)
        ])
        self.scaleLabel = scaleLabel

        sceneView.delegate = self

        let arSession = ARSession()
        sceneView.session = arSession
        arSession.delegate = self
        let config = ARWorldTrackingConfiguration()
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        self.arSession = arSession

        return sceneView
    }
}

// MARK: - ARSessionDelegate

extension CameraViewFactory : ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        didUpdateFrame?(frame.capturedImage)
    }
}

// MARK: - ARSCNViewDelegate

extension CameraViewFactory : ARSCNViewDelegate {

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            self.detectObjects()
        }
    }

    private func detectObjects() {
        // Calculating pixel
        let halfScaleWidth = scaleWidth / 2
        let startFrameValue = CGPoint(x: sceneView.center.x - halfScaleWidth, y: sceneView.center.y)
        let endFrameValue = CGPoint(x: sceneView.center.x + halfScaleWidth, y: sceneView.center.y)
        let deltaX = Float(endFrameValue.x - startFrameValue.x)
        let deltaY = Float(endFrameValue.y - startFrameValue.y)
        let lengthInPoint = sqrtf(deltaX * deltaX + deltaY * deltaY)          // in point
        let lengthInPixel = lengthInPoint * Float(UIScreen.main.scale)        // in pixel

        // Calculating length
        if let startWorldVector = sceneView.realWorldVector(screenPos: startFrameValue),
            let endWorldVector = sceneView.realWorldVector(screenPos: endFrameValue) {
            let lengthInMeter = startWorldVector.distance(from: endWorldVector)
            didUpdateScale?(lengthInPixel, lengthInMeter * 100)
        }
    }
}
