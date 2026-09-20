import Accelerate
import CoreGraphics
import Foundation

struct Point {
    let x: Double
    let y: Double
}

// Same per-point operations as origin/main's AccelerateTransformer.pixelForValue.
struct MainEraTransformer {
    let matrix: [Double]
    func pixelForValue(_ point: Point) -> CGPoint {
        var result = [Double](repeating: 0, count: 3)
        let input = [Double(point.x), Double(point.y), 1]
        vDSP_mmulD(input, 1, matrix, 1, &result, 1, 1, 3, 3)
        return CGPoint(x: result[0], y: result[1])
    }
}

struct AffinePointTransformer {
    let transform: CGAffineTransform
    func pixelForValue(_ point: Point) -> CGPoint {
        CGPoint(x: point.x, y: point.y).applying(transform)
    }
}

@inline(never)
func mainEraBatch(_ points: [Point], transform: CGAffineTransform) -> Double {
    let converter = MainEraTransformer(matrix: [
        transform.a, transform.b, 0,
        transform.c, transform.d, 0,
        transform.tx, transform.ty, 1
    ])
    var checksum = 0.0
    for point in points {
        let pixel = converter.pixelForValue(point)
        checksum += pixel.x * 0.25 + pixel.y * 0.5
    }
    return checksum
}

@inline(never)
func affineBatch(_ points: [Point], transform: CGAffineTransform) -> Double {
    let converter = AffinePointTransformer(transform: transform)
    var checksum = 0.0
    for point in points {
        let pixel = converter.pixelForValue(point)
        checksum += pixel.x * 0.25 + pixel.y * 0.5
    }
    return checksum
}

let origin = Double(CommandLine.arguments.dropFirst().first ?? "1720000000000")!
let pointCount = 5_000
let batches = 400
let rounds = 7
let points = (0..<pointCount).map { index in
    Point(x: origin + Double(index) * 60_000,
          y: 65_000 + sin(Double(index) * 0.017) * 1_500)
}
let scaleX = 1_200 / (Double(pointCount - 1) * 60_000)
let scaleY = 600.0 / 4_000
let base = CGAffineTransform(a: scaleX, b: 0, c: 0, d: -scaleY,
                            tx: -origin * scaleX, ty: 600 + 63_000 * scaleY)

var maxCoordinateError = 0.0
for shift in 0..<11 {
    var transform = base
    transform.tx += Double(shift) * 0.125
    let old = MainEraTransformer(matrix: [transform.a, 0, 0, 0, transform.d, 0, transform.tx, transform.ty, 1])
    let new = AffinePointTransformer(transform: transform)
    for point in points {
        let lhs = old.pixelForValue(point)
        let rhs = new.pixelForValue(point)
        maxCoordinateError = max(maxCoordinateError, abs(lhs.x - rhs.x), abs(lhs.y - rhs.y))
    }
}
precondition(maxCoordinateError <= 0.000001, "Pixel-coordinate mismatch")

func measure(_ body: ([Point], CGAffineTransform) -> Double) -> (milliseconds: Double, checksum: Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    var checksum = 0.0
    for batch in 0..<batches {
        var transform = base
        // Vary each batch to prevent an optimizer from hoisting a repeated conversion.
        transform.tx += Double(batch % 11) * 0.125
        checksum += body(points, transform)
    }
    let nanoseconds = DispatchTime.now().uptimeNanoseconds - start
    return (Double(nanoseconds) / 1_000_000, checksum)
}

// Warm up both paths, then alternate measurement order to reduce ordering bias.
let warmOld = measure(mainEraBatch)
let warmNew = measure(affineBatch)
var oldTimes: [Double] = []
var newTimes: [Double] = []
var outputChecksum = warmOld.checksum + warmNew.checksum
for round in 0..<rounds {
    let old: (milliseconds: Double, checksum: Double)
    let new: (milliseconds: Double, checksum: Double)
    if round.isMultiple(of: 2) {
        old = measure(mainEraBatch)
        new = measure(affineBatch)
    } else {
        new = measure(affineBatch)
        old = measure(mainEraBatch)
    }
    precondition(abs(old.checksum - new.checksum) < 0.01, "Checksum mismatch")
    oldTimes.append(old.milliseconds)
    newTimes.append(new.milliseconds)
    outputChecksum += old.checksum + new.checksum
    print(String(format: "round %d: main-era %.3f ms; affine %.3f ms; ratio %.2fx; checksums %.6f / %.6f",
                 round + 1, old.milliseconds, new.milliseconds, old.milliseconds / new.milliseconds,
                 old.checksum, new.checksum))
}
let oldMedian = oldTimes.sorted()[rounds / 2]
let newMedian = newTimes.sorted()[rounds / 2]
print("points per batch: \(pointCount); batches per round: \(batches); timed rounds: \(rounds)")
print(String(format: "median: main-era %.3f ms; affine %.3f ms; ratio %.2fx", oldMedian, newMedian, oldMedian / newMedian))
print(String(format: "per 5000-point batch: main-era %.6f ms; affine %.6f ms", oldMedian / Double(batches), newMedian / Double(batches)))
print(String(format: "max coordinate error: %.12g pixels; output checksum: %.6f", maxCoordinateError, outputChecksum))
