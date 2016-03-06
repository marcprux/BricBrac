//
//  BricIO+Cocoa.swift
//  Bric-à-brac
//
//  Created by Marc Prud'hommeaux on 7/20/15.
//  Copyright © 2015 io.glimpse. All rights reserved.
//

#if !os(Linux) // should work eventually, but build bugs in swift-DEVELOPMENT-SNAPSHOT-2016-02-25-a-ubuntu14.04
import Foundation
import CoreFoundation

public extension Bric {

    /// Validates the given JSON string and throws an error if there was a problem
    public static func parseCocoa(string: String, options: JSONParser.Options = .CocoaCompat) throws -> NSObject {
        return try FoundationBricolage.parseJSON(Array(string.unicodeScalars), options: options).object
    }

    /// Validates the given array of unicode scalars and throws an error if there was a problem
    public static func parseCocoa(scalars: [UnicodeScalar], options: JSONParser.Options = .CocoaCompat) throws -> NSObject {
        return try FoundationBricolage.parseJSON(scalars, options: options).object
    }
}


/// Bricolage that represents the elements as Cocoa NSObject types with reference semantics
public final class FoundationBricolage: NSObject, Bricolage {
    public typealias NulType = NSNull
    public typealias BolType = NSNumber
    public typealias StrType = NSString
    public typealias NumType = NSNumber
    public typealias ArrType = NSMutableArray
    public typealias ObjType = NSMutableDictionary

    public let object: NSObject

    public init(str: StrType) { self.object = str }
    public init(num: NumType) { self.object = num }
    public init(bol: BolType) { self.object = bol }
    public init(arr: ArrType) { self.object = arr }
    public init(obj: ObjType) { self.object = obj }
    public init(nul: NulType) { self.object = nul }

    public static func createNull() -> NulType { return NSNull() }
    public static func createTrue() -> BolType { return true }
    public static func createFalse() -> BolType { return false }
    public static func createObject() -> ObjType { return ObjType() }
    public static func createArray() -> ArrType { return ArrType() }

    public static func createString(scalars: [UnicodeScalar]) -> StrType? {
        return String(String.UnicodeScalarView() + scalars) as NSString
    }

    public static func createNumber(scalars: [UnicodeScalar]) -> NumType? {
        if let str: NSString = createString(Array(scalars)) {
            return NSDecimalNumber(string: str as String) // needed for 0.123456789e-12
        } else {
            return nil
        }
    }

    public static func putKeyValue(obj: ObjType, key: StrType, value: FoundationBricolage) -> ObjType {
        obj.setObject(value.object, forKey: key)
        return obj
    }

    public static func putElement(arr: ArrType, element: FoundationBricolage) -> ArrType {
        arr.addObject(element.object)
        return arr
    }
}


extension FoundationBricolage : Bricable, Bracable {
    public func bric() -> Bric {
        return FoundationBricolage.toBric(object)
    }

    private static let bolTypes = Set(arrayLiteral: "B", "c") // "B" on 64-bit, "c" on 32-bit
    private static func toBric(object: AnyObject) -> Bric {
        if let bol = object as? BolType where bolTypes.contains(String.fromCString(bol.objCType) ?? "") {
            return Bric.Bol(bol as Bool)
        }
        if let str = object as? StrType {
            return Bric.Str(str as String)
        }
        if let num = object as? NumType {
            return Bric.Num(num as Double)
        }
        if let arr = object as? ArrType {
            return Bric.Arr(arr.map(toBric))
        }
        if let obj = object as? ObjType {
            var dict: [String: Bric] = [:]
            for (key, value) in obj {
                dict[String(key)] = toBric(value)
            }
            return Bric.Obj(dict)
        }

        return Bric.Nul
    }

    public static func brac(bric: Bric) -> FoundationBricolage {
        switch bric {
        case .Nul:
            return FoundationBricolage(nul: FoundationBricolage.createNull())
        case .Bol(let bol):
            return FoundationBricolage(bol: bol ? FoundationBricolage.createTrue() : FoundationBricolage.createFalse())
        case .Str(let str):
            return FoundationBricolage(str: str)
        case .Num(let num):
            return FoundationBricolage(num: num)
        case .Arr(let arr):
            let nsarr = FoundationBricolage.createArray()
            for a in arr {
                FoundationBricolage.putElement(nsarr, element: FoundationBricolage.brac(a))
            }
            return FoundationBricolage(arr: nsarr)
        case .Obj(let obj):
            let nsobj = FoundationBricolage.createObject()
            for (k, v) in obj {
                FoundationBricolage.putKeyValue(nsobj, key: k, value: FoundationBricolage.brac(v))
            }
            return FoundationBricolage(obj: nsobj)
        }
    }
}

/// Bricolage that represents the elements as Core Foundation types with reference semantics
public final class CoreFoundationBricolage: Bricolage {
    public typealias NulType = CFNull
    public typealias BolType = CFBoolean
    public typealias StrType = CFString
    public typealias NumType = CFNumber
    public typealias ArrType = CFMutableArray
    public typealias ObjType = CFMutableDictionary

    public let ptr: UnsafePointer<AnyObject>

    public init(str: StrType) { self.ptr = UnsafePointer(Unmanaged.passRetained(str).toOpaque()) }
    public init(num: NumType) { self.ptr = UnsafePointer(Unmanaged.passRetained(num).toOpaque()) }
    public init(bol: BolType) { self.ptr = UnsafePointer(Unmanaged.passRetained(bol).toOpaque()) }
    public init(arr: ArrType) { self.ptr = UnsafePointer(Unmanaged.passRetained(arr).toOpaque()) }
    public init(obj: ObjType) { self.ptr = UnsafePointer(Unmanaged.passRetained(obj).toOpaque()) }
    public init(nul: NulType) { self.ptr = UnsafePointer(Unmanaged.passRetained(nul).toOpaque()) }

    deinit {
        Unmanaged<AnyObject>.fromOpaque(COpaquePointer(ptr)).release()
    }

    public static func createNull() -> NulType { return kCFNull }
    public static func createTrue() -> BolType { return kCFBooleanTrue }
    public static func createFalse() -> BolType { return kCFBooleanFalse }
    public static func createObject() -> ObjType { return CFDictionaryCreateMutable(nil, 0, nil, nil) }
    public static func createArray() -> ArrType { return CFArrayCreateMutable(nil, 0, nil) }

    public static func createString(scalars: [UnicodeScalar]) -> StrType? {
        return String(String.UnicodeScalarView() + scalars)
    }

    public static func createNumber(scalars: [UnicodeScalar]) -> NumType? {
        if let str = createString(Array(scalars)) {
            return NSDecimalNumber(string: str as String) // needed for 0.123456789e-12
        } else {
            return nil
        }
    }

    public static func putKeyValue(obj: ObjType, key: StrType, value: CoreFoundationBricolage) -> ObjType {
        CFDictionarySetValue(obj, UnsafePointer<Void>(Unmanaged<CFString>.passRetained(key).toOpaque()), value.ptr)
        return obj
    }

    public static func putElement(arr: ArrType, element: CoreFoundationBricolage) -> ArrType {
        CFArrayAppendValue(arr, element.ptr)
        return arr
    }
}
#endif // #if !os(Linux)
