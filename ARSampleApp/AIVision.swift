//
//  AIVision.swift
//  ARSampleApp
//
//  Created by denkeni on 2018/9/3.
//  Copyright © 2018 Nandalu. All rights reserved.
//

import Foundation
import Vision

final class AIVision {

    /// The pixel buffer being held for analysis; used to serialize Vision requests.
    var currentBuffer: CVPixelBuffer? {
        didSet {
            if currentBuffer != nil {
                classifyCurrentImage()
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

    private lazy var labels : [String] = {
        guard let path = Bundle.main.path(forResource: "labels", ofType: "txt"),
            let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                assertionFailure("Parsing labels.txt error")
                return [String]()
        }
        let lines = content.components(separatedBy: "\n")
        var array = [String]()
        for line in lines {
            let element = line.components(separatedBy: ":")
            if let value = element.last {
                array.append(value)
            }
        }
        return array
    }()
    private var inferences : ((String) -> Void)? = nil

    init(inferences: @escaping (String) -> Void) {
        self.inferences = inferences
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
                        let result = String(format: "%@ (%.2f)", bestLabelElement, maxElement)
                        self.inferences?(result)
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.inferences?("")
            }
        }
    }
}
