//
//  ViewController.swift
//  ARSampleApp
//
//  MIT License
//  Copyright (c) 2018 Denken Chen, Apple Inc., Droids On Roids LLC
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import UIKit
import SceneKit
import WebKit
import AVKit    // for torchModeAuto
//import Network  // for NWPathMonitor

final class ViewController: UIViewController {

    private let cameraViewFactory = CameraViewFactory()
    private var sceneView: SCNView!
    private var cameraButton : CameraButton? = nil

    private var lengthInPixel : Float? = nil
    private var lengthInCentiMeter : Float? = nil

    private lazy var aiVision : AIVision = {
        let ai = AIVision(inference: { (inference, confidence) in
            DispatchQueue.main.async {
                if !self.cameraViewFactory.shouldShowScale {
                    self.title = String(format: "%@ (%.2f)", inference, confidence)
                    if !self.isViewing {
                        self.webView.evaluateJavaScript("doc.show(\"\(inference)\");", completionHandler: nil)
                    }
                }
            }
        })
        return ai
    }()

    private var bottomSheetViewController : BottomSheetViewController? = nil
    lazy var webView : WKWebView = {
        let height = 9 / 10 * view.bounds.height
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 0, height: height))
        return webView
    }()
    private var isViewing = false

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
        cameraView.frame = UIScreen.main.bounds
        sceneView = cameraView
        view = cameraView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        resetValues()
        prepareViewMode()

        NotificationCenter.default.addObserver(self,
            selector: #selector(applicationDidBecomeActive(notification:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    @objc func applicationDidBecomeActive(notification: NSNotification) {
        self.title = ""
        prepareViewMode()
    }

    private func prepareViewMode() {
        // From Settings.bundle
        let isCameraMode = UserDefaults.standard.bool(forKey: "cameraMode")
        if isCameraMode {
            if cameraButton == nil {
                let cameraButton = CameraButton(currentData: { () -> (snapshot: UIImage, lengthInPixel: Float?, lengthInCentiMeter: Float?) in
                    return (self.sceneView.snapshot(), self.lengthInPixel, self.lengthInCentiMeter)
                })
                cameraButton.translatesAutoresizingMaskIntoConstraints = false
                self.view.addSubview(cameraButton)
                NSLayoutConstraint.activate([
                    cameraButton.bottomAnchor.constraint(equalTo: self.sceneView.safeAreaLayoutGuide.bottomAnchor, constant: -20.0),
                    cameraButton.centerXAnchor.constraint(equalTo: self.sceneView.centerXAnchor)
                    ])
                self.cameraButton = cameraButton
            }
            navigationController?.setNavigationBarHidden(false, animated: true)
            cameraButton?.isHidden = false
            bottomSheetViewController?.view.removeFromSuperview()
            bottomSheetViewController?.removeFromParent()
        } else {
            if bottomSheetViewController == nil {
                let bottomSheetViewController = BottomSheetViewController(type: .plain)
                bottomSheetViewController.tableView.tableHeaderView = webView
                bottomSheetViewController.bottomSheetDelegate = self
                bottomSheetViewController.heights = (1 / 5, 9 / 10, 9 / 10)
                // Use NWPathMonitor on iOS 12 instead of Reachability
                // See: WWDC 2018 Session 715
                /*
                if #available(iOS 12.0, *) {
                    NetworkMonitor.shared.startNotifier()
                }
                 */
                let loadWebContent = {
                    guard let url = URL(string: "https://plant-tw.github.io/PlantsData/") else { return }
                    let urlRequest = URLRequest(url: url)
                    self.webView.load(urlRequest)
                    // TODO: offline mode
                }
                loadWebContent()
                /*
                if #available(iOS 12.0, *) {
                    NetworkMonitor.shared.connectionDidChanged = { (isConnected: Bool) -> Void in
                        // This is called at app launch, too
                        if isConnected {
                            DispatchQueue.main.async {
                                loadWebContent()
                            }
                            NetworkMonitor.shared.stopNotifier()
                        }
                    }
                } else {
                    // "Avoid checking reachability before starting a connection"
                    loadWebContent()    // load content anyway
                }
                 */
                self.bottomSheetViewController = bottomSheetViewController
            }
            navigationController?.setNavigationBarHidden(true, animated: true)
            cameraButton?.isHidden = true
            if let bottomSheetViewController = bottomSheetViewController {
                if bottomSheetViewController.parent == nil {
                    addChild(bottomSheetViewController)
                    bottomSheetViewController.show(in: view, initial: .collapsed)
                    bottomSheetViewController.didMove(toParent: self)
                }
            }
        }
        // From Settings.bundle
        let isTorchModeAuto = UserDefaults.standard.bool(forKey: "torchModeAuto")
        if let device = AVCaptureDevice.default(for: .video) {
            if device.hasTorch {
                do {
                    try device.lockForConfiguration()
                    // TODO: It's possible to continuously update torch mode. See: https://stackoverflow.com/a/28298472/3796488
                    if isTorchModeAuto {
                        if device.isTorchModeSupported(.auto) {
                            device.torchMode = .auto
                        }
                    } else {
                        if device.isTorchModeSupported(.off) {
                            device.torchMode = .off
                        }
                    }
                    device.unlockForConfiguration()
                } catch {
                    print("Torch could not be used")
                }
            }
        }
    }
}

// MARK: - Touch and hold to measure length

extension ViewController {

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let isCameraMode = UserDefaults.standard.bool(forKey: "cameraMode")
        if !isCameraMode {
            return
        }
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

// MARK: - BottomSheetViewDelegate

extension ViewController : BottomSheetViewDelegate {

    func didMove(to percentage: Float) {
        if percentage == 1.0 {
            webView.evaluateJavaScript("doc.loadImages();", completionHandler: nil)
        }
        isViewing = (percentage > 0.5)
    }
}

// MARK: -
/*
@available(iOS 12.0, *)
struct NetworkMonitor {

    static var shared = NetworkMonitor()
    private init() {}

    private let monitor = NWPathMonitor()

    var currentPath : NWPath {
        return monitor.currentPath
    }

    var connectionDidChanged : ((Bool) -> Void)? = nil

    func startNotifier() {
        monitor.pathUpdateHandler = {(path: NWPath) -> Void in
            var isConnected = false
            for interface in path.availableInterfaces {
                switch interface.type {
                case .cellular, .wifi, .wiredEthernet:
                    isConnected = true
                default:
                    break
                }
            }
            NetworkMonitor.shared.connectionDidChanged?(isConnected)
        }
        monitor.start(queue: DispatchQueue.global(qos: .userInteractive))
    }

    func stopNotifier() {
        monitor.cancel()
    }
}
*/
