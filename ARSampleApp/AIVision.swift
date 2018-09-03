//
//  AIVision.swift
//  ARSampleApp
//
//  MIT License
//  Copyright (c) 2018 Denken Chen, Apple Inc., Droids On Roids LLC
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

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
    private var inference : ((String) -> Void)? = nil

    init(inference: @escaping (String) -> Void) {
        self.inference = inference
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
        guard let bestResult = classifications.first(where: { result in result.confidence > 0.5 }),
            // From: https://gist.github.com/otmb/7adf88882d2995ca63ad0ee5a0d3f91a
            let featureArray = bestResult.featureValue.multiArrayValue else {
                print("bestResult or featureArray not available")
                return
        }
        let length = featureArray.count
        let doublePtr = featureArray.dataPointer.bindMemory(to: Double.self, capacity: length)
        let doubleBuffer = UnsafeBufferPointer(start: doublePtr, count: length)
        let output = Array(doubleBuffer)
        // Notice: We use confidence from multiarray, not `result.confidence` above
        if let maxConfidence = output.max(),
            let maxIndex = output.index(of: maxConfidence) {
            if maxIndex < labels.count && maxConfidence > 0.7 {
                let bestLabelElement = labels[maxIndex]
                let result = String(format: "%@ (%.2f)", bestLabelElement, maxConfidence)
                self.inference?(result)
                return
            }
        }
    }
}
