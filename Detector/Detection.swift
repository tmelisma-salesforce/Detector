//
//  Detection.swift
//  Detector
//
//  Created by Toni Melisma on 4/16/25.
//

import Foundation // For UUID
import CoreGraphics // For CGRect

/// Represents a single detected object after parsing and NMS.
struct Detection: Identifiable {
    /// Unique identifier for SwiftUI lists.
    let id = UUID()
    /// Bounding box in normalized coordinates (origin top-left, 0.0 to 1.0).
    let box: CGRect
    /// Index corresponding to the class label in `ObjectDetector.classNames`.
    let classIndex: Int
    /// Confidence score (derived from max class probability in this case).
    let confidence: Float

    /// Convenience computed property to get the class label string.
    var label: String? {
        // Access the static classNames dictionary from ObjectDetector
        guard classIndex >= 0 && classIndex < ObjectDetector.classNames.count else {
            // Handle invalid index if necessary
            return nil // Or return "Unknown" or similar
        }
        return ObjectDetector.classNames[classIndex]
    }
}

