//
//  CameraButton.swift
//  ARSampleApp
//
//  Created by denkeni on 2018/9/3.
//  Copyright © 2018 Nandalu. All rights reserved.
//

import UIKit
import CoreMotion
import CoreLocation
import MobileCoreServices   // for kUTTypeJPEG

final class CameraButton : UIButton {

    private var photos : [Data] = [Data]()
    private var exifs : [ExifUserComment] = [ExifUserComment]()
    private var recordTimer : Timer? = nil {
        willSet {
            if newValue == nil {
                alpha = 1.0
            } else {
                alpha = 0.3
            }
        }
    }
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var currentData: (() -> (snapshot: UIImage, lengthInPixel: Float?, lengthInCentiMeter: Float?))? = nil

    init(currentData: @escaping () -> (snapshot: UIImage, lengthInPixel: Float?, lengthInCentiMeter: Float?)) {
        self.currentData = currentData
        super.init(frame: .zero)

        setImage(UIImage(named: "circle-160"), for: .normal)
        addTarget(self, action: #selector(tap), for: .touchUpInside)

        // Device motion manager
        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical)

        // Location permission
        switch CLLocationManager.authorizationStatus() {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            UIAlertController.ptw_presentAlert(with: "Without location information, prediction might be inaccurate, and data collecting will be disabled (You can change settings later).")
        default:
            break
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Button action

    @objc private func tap() {
        if recordTimer == nil {
            startTakingPhotos()
        } else {
            stopTakingPhotos()
        }
    }

    private func startTakingPhotos() {
        recordTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(takePhoto), userInfo: nil, repeats: true)
    }

    @objc private func takePhoto() {
        guard let currentData = currentData else { return }
        let (snapshot, px, cm) = currentData()
        guard let lengthInPixel = px, let lengthInCentiMeter = cm else {
            // Stop the timer
            recordTimer?.invalidate()
            recordTimer = nil
            UIAlertController.ptw_presentAlert(with: "AR sensor not ready")
            return
        }
        guard let imgData = UIImageJPEGRepresentation(snapshot, 1),
            let roll = motionManager.deviceMotion?.attitude.roll,
            let pitch = motionManager.deviceMotion?.attitude.pitch,
            let yaw = motionManager.deviceMotion?.attitude.yaw else {
                // Stop the timer
                recordTimer?.invalidate()
                recordTimer = nil
                UIAlertController.ptw_presentAlert(with: "motion sensor not ready")
                return
        }
        guard let userLocation = locationManager.location else {
            let alert = UIAlertController(title: "Location is disabled", message: "We need location information to collect better data.", preferredStyle: .alert)
            let changeSetting = UIAlertAction(title: "Change settings", style: .default, handler: { (action) in
                guard let url = URL(string: UIApplicationOpenSettingsURLString) else { return }
                UIApplication.shared.open(url, completionHandler: nil)
            })
            let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            alert.addAction(changeSetting)
            alert.addAction(cancel)
            if let delegate = UIApplication.shared.delegate as? AppDelegate, let rootVc = delegate.window?.rootViewController {
                rootVc.present(alert, animated: true, completion: nil)
            }
            // Stop the timer
            recordTimer?.invalidate()
            recordTimer = nil
            return
        }
        let exifUserComment = ExifUserComment(lengthInPixel: lengthInPixel,
                                              lengthInCentiMeter: lengthInCentiMeter,
                                              roll: roll,
                                              pitch: pitch,
                                              yaw: yaw,
                                              latitude: userLocation.coordinate.latitude,
                                              longitude: userLocation.coordinate.longitude)
        exifs.append(exifUserComment)
        photos.append(imgData)
    }

    private func stopTakingPhotos() {
        // Stop the timer
        recordTimer?.invalidate()
        recordTimer = nil

        // Early check
        if photos.count != exifs.count {
            UIAlertController.ptw_presentAlert(with: "photos and exifs count not consistent")
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
                UIAlertController.ptw_presentAlert(with: error.localizedDescription)
                return
            }
        } else {
            UIAlertController.ptw_presentAlert(with: "Random collision! Try again.")
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
                    UIAlertController.ptw_presentAlert(with: "Error occurs when preparing destination or source")
                    return
            }
            CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
            CGImageDestinationFinalize(destination)
        }
        // Ending and removing
        photos.removeAll()
        exifs.removeAll()
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
