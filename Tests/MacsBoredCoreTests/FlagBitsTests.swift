import XCTest
@testable import MacsBoredCore

final class FlagBitsTests: XCTestCase {
    // CGEventFlags values, written out so the test doesn't lean on the code under test.
    private let shift: UInt64 = 0x20000, control: UInt64 = 0x40000, option: UInt64 = 0x80000, command: UInt64 = 0x100000
    private let capsLock: UInt64 = 0x10000, numericPad: UInt64 = 0x200000
    private let leftControl: UInt64 = 0x1, leftCommand: UInt64 = 0x8, rightCommand: UInt64 = 0x10, rightControl: UInt64 = 0x2000
    private let leftShift: UInt64 = 0x2, leftOption: UInt64 = 0x20, rightOption: UInt64 = 0x40

    func testReadsTheFourModifiers() {
        XCTAssertEqual(FlagBits.modifiers(command | shift | capsLock), [.command, .shift])
        XCTAssertEqual(FlagBits.modifiers(control | option), [.control, .option])
        XCTAssertEqual(FlagBits.modifiers(capsLock | numericPad), [])
    }

    func testSwappingMovesTheSideBitsAcross() {
        let raw = command | rightCommand | shift | leftShift | numericPad
        let rewritten = FlagBits.rewrite(raw, to: [.control, .shift], swapping: (.command, .control))
        XCTAssertEqual(rewritten, control | rightControl | shift | leftShift | numericPad)
    }

    func testSwappingControlGivesTheLeftCommandKey() {
        let rewritten = FlagBits.rewrite(control | leftControl, to: .command, swapping: (.command, .control))
        XCTAssertEqual(rewritten, command | leftCommand)
    }

    func testSwappingOptionAndCommandMovesTheirSidesAcross() {
        let rewritten = FlagBits.rewrite(option | rightOption | shift | leftShift, to: [.command, .shift],
                                         swapping: (.command, .option))
        XCTAssertEqual(rewritten, command | rightCommand | shift | leftShift)
        XCTAssertEqual(FlagBits.rewrite(command | leftCommand, to: .option, swapping: (.command, .option)), option | leftOption)
    }

    func testAddedModifiersComeFromTheLeftKeysAndOtherBitsSurvive() {
        let rewritten = FlagBits.rewrite(capsLock, to: .hyper, swapping: nil)
        XCTAssertEqual(rewritten, capsLock | control | leftControl | option | leftOption | shift | leftShift
                       | command | leftCommand)
    }

    func testRemovedModifiersLoseBothSides() {
        let rewritten = FlagBits.rewrite(command | leftCommand | rightCommand | shift | leftShift, to: .shift,
                                         swapping: nil)
        XCTAssertEqual(rewritten, shift | leftShift)
    }
}
