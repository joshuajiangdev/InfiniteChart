//
//  Transformable.swift
//  
//
//  Created by Joshua Jiang on 8/21/24.
//

enum TransformableAxis {
    case horizontal
    case vertical
}

@MainActor
protocol Transformable {
    var transformerProvider: (any TransformerProviding)? { get set }
    var transformableAxes: [TransformableAxis] { get }
}
