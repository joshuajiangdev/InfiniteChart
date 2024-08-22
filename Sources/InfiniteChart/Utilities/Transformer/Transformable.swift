//
//  Transformable.swift
//  
//
//  Created by Joshua Jiang on 8/21/24.
//

import Combine

enum TransformableAxis {
    case horizontal
    case vertical
}

protocol Transformable {
    associatedtype TransformerType: Transformer
    
    var transformerProvider: (any TransformerProviding)? { get set }
    var transformableAxes: [TransformableAxis] { get }
    var transformerStream: AnyPublisher<TransformerType, Never>? { get }
}
