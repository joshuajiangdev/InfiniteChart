//
//  TransformerProviding.swift
//  
//
//  Created by Joshua Jiang on 8/20/24.
//

import Foundation
import Combine
import UIKit

protocol TransformerProviding {
    
    associatedtype T: Transformer
    
    var transformerStream: AnyPublisher<T, Never> { get }
    var chartWidth: CGFloat { get }
    var chartHeight: CGFloat { get }
    
    func zoom(scaleX: CGFloat, scaleY: CGFloat, x: CGFloat, y: CGFloat)
    
    func translate(delta: CGPoint)
}
