//
//  ObjectDetector.swift
//  Detector
//
//  Created by Toni Melisma on 4/16/25.
//

import Vision // Using iOS 18 APIs where applicable, result types might bridge from older VN types
import CoreML
import UIKit // For UIImage, CGRect, CGImagePropertyOrientation
import SwiftUI // For ObservableObject
import ImageIO // For CGImagePropertyOrientation

// Make ObjectDetector an ObservableObject to use with @StateObject in ContentView
class ObjectDetector: ObservableObject {
    @Published private(set) var setupError: String?
    private var visionModelContainer: Vision.CoreMLModelContainer?

    // Model parameters
    private let modelName = "yolo11x" // Ensure this matches the .mlpackage name

    // Output feature names from the nms=True model
    private let coordinatesOutputName = "coordinates"
    private let confidenceOutputName = "confidence"

    // Class names mapping (ensure this matches your model training)
    static let classNames: [Int: String] = [
        0: "person", 1: "bicycle", 2: "car", 3: "motorcycle", 4: "airplane",
        5: "bus", 6: "train", 7: "truck", 8: "boat", 9: "traffic light",
        10: "fire hydrant", 11: "stop sign", 12: "parking meter", 13: "bench",
        14: "bird", 15: "cat", 16: "dog", 17: "horse", 18: "sheep", 19: "cow",
        20: "elephant", 21: "bear", 22: "zebra", 23: "giraffe", 24: "backpack",
        25: "umbrella", 26: "handbag", 27: "tie", 28: "suitcase", 29: "frisbee",
        30: "skis", 31: "snowboard", 32: "sports ball", 33: "kite",
        34: "baseball bat", 35: "baseball glove", 36: "skateboard", 37: "surfboard",
        38: "tennis racket", 39: "bottle", 40: "wine glass", 41: "cup", 42: "fork",
        43: "knife", 44: "spoon", 45: "bowl", 46: "banana", 47: "apple",
        48: "sandwich", 49: "orange", 50: "broccoli", 51: "carrot", 52: "hot dog",
        53: "pizza", 54: "donut", 55: "cake", 56: "chair", 57: "couch",
        58: "potted plant", 59: "bed", 60: "dining table", 61: "toilet", 62: "tv",
        63: "laptop", 64: "mouse", 65: "remote", 66: "keyboard", 67: "cell phone",
        68: "microwave", 69: "oven", 70: "toaster", 71: "sink", 72: "refrigerator",
        73: "book", 74: "clock", 75: "vase", 76: "scissors", 77: "teddy bear",
        78: "hair drier", 79: "toothbrush"
    ]


    init() {
        loadModel()
    }

    private func loadModel() {
        print("[DEBUG ObjectDetector] Loading model '\(modelName)' (nms=True version)...")
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            let errorMsg = "Model file '\(modelName).mlmodelc' not found. Ensure '\(modelName).mlpackage' (nms=True version) is added to the project target."
            print("[ERROR ObjectDetector] \(errorMsg)")
            DispatchQueue.main.async { self.setupError = errorMsg }
            return
        }

        do {
            let mlModel = try MLModel(contentsOf: modelURL)
            self.visionModelContainer = try Vision.CoreMLModelContainer(model: mlModel, featureProvider: nil)
            print("[DEBUG ObjectDetector] Model loaded and container created successfully.")
        } catch {
            let errorMsg = "Failed to load Core ML model or create container: \(error.localizedDescription)"
            print("[ERROR ObjectDetector] \(errorMsg)")
            print("[ERROR ObjectDetector] Details: \(error)")
            DispatchQueue.main.async { self.setupError = errorMsg }
            self.visionModelContainer = nil
        }
    }

    // MARK: - Orientation Helper

    /// Converts UIImage.Orientation to CGImagePropertyOrientation used by Vision.
    private func cgImageOrientation(from imageOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch imageOrientation {
            case .up: return .up
            case .down: return .down
            case .left: return .left
            case .right: return .right
            case .upMirrored: return .upMirrored
            case .downMirrored: return .downMirrored
            case .leftMirrored: return .leftMirrored
            case .rightMirrored: return .rightMirrored
            @unknown default: return .up // Default to up if unknown
        }
    }

    // MARK: - Detection Execution (Revised for nms=True model & RecognizedObjectObservation)

    func performDetection(on uiImage: UIImage) async throws -> [Detection] {
        print("[DEBUG ObjectDetector] Starting performDetection (Model: \(modelName))...")
        guard let container = visionModelContainer else {
            print("[ERROR ObjectDetector] Model container not loaded.")
            throw DetectionError.modelNotLoaded
        }
        guard let cgImage = uiImage.cgImage else {
            print("[ERROR ObjectDetector] Could not create CGImage.")
            throw DetectionError.cgImageCreationFailed
        }

        // *** Get Correct Orientation ***
        let imageOrientation = uiImage.imageOrientation
        let visionOrientation = cgImageOrientation(from: imageOrientation)
        print("[DEBUG ObjectDetector] Image Orientation: \(imageOrientation.rawValue), Vision Orientation: \(visionOrientation.rawValue)")


        // 1. Create Vision Request
        print("[DEBUG ObjectDetector] Creating Vision.CoreMLRequest...")
        let request = Vision.CoreMLRequest(model: container)

        // 2. Perform Request with Correct Orientation
        print("[DEBUG ObjectDetector] Performing request on CGImage (orientation: \(visionOrientation.rawValue))...")
        let observations: [any VisionObservation]
        do {
             // *** Pass Correct Orientation ***
             observations = try await request.perform(on: cgImage, orientation: visionOrientation)
             print("[DEBUG ObjectDetector] Vision request performed. Received \(observations.count) observations.")
        } catch {
             print("[ERROR ObjectDetector] Vision request failed: \(error)")
             throw DetectionError.detectionFailed(error)
        }

        // 3. Process Observations (Cast to RecognizedObjectObservation)
        print("[DEBUG ObjectDetector] Processing observations (expecting RecognizedObjectObservation)...")
        let recognizedObservations = observations.compactMap { $0 as? Vision.RecognizedObjectObservation }
        print("[DEBUG ObjectDetector] Found \(recognizedObservations.count) RecognizedObjectObservation(s).")

        if recognizedObservations.isEmpty && !observations.isEmpty {
             print("[WARN ObjectDetector] Casting to RecognizedObjectObservation failed. Actual observation types:")
             for (index, obs) in observations.enumerated() { print("  Observation \(index): \(type(of: obs))") }
             throw DetectionError.unexpectedResultType
        }

        // 4. Convert to Detection results
        var finalDetections: [Detection] = []
        print("[DEBUG ObjectDetector] Converting \(recognizedObservations.count) RecognizedObjectObservation(s) to [Detection]...")

        for observation in recognizedObservations {
            guard let topLabel = observation.labels.first else {
                print("[WARN ObjectDetector] Skipping observation \(observation.uuid) because it has no labels.")
                continue
            }

            let confidence = topLabel.confidence
            let labelName = topLabel.identifier
            // print("[DETAILED LOG Convert] Trying to find index for label name: '\(labelName)'")

            guard let classIndex = ObjectDetector.classNames.first(where: { $1 == labelName })?.key else {
                 print("[WARN ObjectDetector] Skipping observation \(observation.uuid) because label name '\(labelName)' was not found in classNames dictionary.")
                 continue
            }
            // print("[DETAILED LOG Convert] Found Class Index: \(classIndex) for label name: '\(labelName)'")

            // Bounding box from Vision (NormalizedRect, bottom-left origin)
            // Vision coordinates are relative to the image *as it was processed* (using the orientation we provided)
            let visionRect = observation.boundingBox

            // Convert to CGRect with normalized coordinates and top-left origin for SwiftUI
            let normalizedBox = CGRect(
                x: visionRect.origin.x,
                y: 1.0 - visionRect.origin.y - visionRect.height, // Convert Y origin
                width: visionRect.width,
                height: visionRect.height
            )

             // Clamp normalized coordinates to [0, 1] to ensure validity
             let clampedBox = CGRect(
                 x: max(0.0, min(1.0, normalizedBox.origin.x)),
                 y: max(0.0, min(1.0, normalizedBox.origin.y)),
                 width: max(0.0, min(1.0 - normalizedBox.origin.x, normalizedBox.width)),
                 height: max(0.0, min(1.0 - normalizedBox.origin.y, normalizedBox.height))
             )

            if clampedBox.width > 0 && clampedBox.height > 0 {
                let detection = Detection(box: clampedBox, classIndex: classIndex, confidence: confidence)
                finalDetections.append(detection)
                if finalDetections.count <= 10 { // Log first few final detections
                    print("[DETAILED LOG Convert] Converted Detection \(finalDetections.count): Box=\(detection.box), Class=\(detection.classIndex) (\(detection.label ?? "??")), Conf=\(String(format: "%.3f", detection.confidence))")
                    // print("    (Source: UUID=\(observation.uuid), VisionRect=\(visionRect), TopLabelID='\(topLabel.identifier)', TopLabelConf=\(topLabel.confidence))")
                }
            } else {
                 print("[WARN ObjectDetector Convert] Skipping observation \(observation.uuid) (Label: '\(labelName)') due to zero size box after conversion/clamping: \(clampedBox)")
            }
        }

        print("[DEBUG ObjectDetector] Finished conversion. Produced \(finalDetections.count) final detections.")
        return finalDetections
    }
}

