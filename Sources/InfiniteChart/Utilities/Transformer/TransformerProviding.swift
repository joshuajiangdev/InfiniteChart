//
//  TransformerProviding.swift
//  
//
//  Created by Joshua Jiang on 8/20/24.
//

import Foundation
import Combine

protocol TransformerProviding {
    associatedtype T: Transformer
    var transformerStream: AnyPublisher<T, Never> { get }
}
