//
//  BricBracTests.swift
//  Bric-à-brac
//
//  Created by Marc Prud'hommeaux on 6/14/15.
//  Copyright © 2015 io.glimpse. All rights reserved.
//

import XCTest
import BricBrac
import JavaScriptCore


// TODO: implement this in BricBrac once we have Swift 4 support for conditional protocol conformance

extension AutoBricBrac {
    static func bricr<T, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11>(_ `init`: (A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11) -> T, _ keys: (String, String, String, String, String, String, String, String, String, String, String), accessor: (T) -> (A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11)) -> Int {
        return 1
    }
}

extension Car {
    static let make = bricr(Car.init,
                            ("manufacturer", "model", "displacement", "year", "cylinders", "transmissionType", "drive", "cityMileage", "highwayMileage", "fuel", "class")) {x in
                                (x.manufacturer, x.model, x.displacement, x.year, x.cylinders, x.transmissionType, x.drive, x.cityMileage, x.highwayMileage, x.fuel, x.class) }
}

class BricBracTests : XCTestCase {

    func testInitString() {
        dump(Mirror(reflecting: Car.make).children.first?.label)
//        XCTAssertEqual("\(type(of: Car.make))", "(String, Optional<String>, Double, UInt16, Cylinders, String, Drive, Int, Int, Fuel, Class) -> Car")
    }
    
    func testBricConversion() {
        let bric: Bric = ["a": [1, 2, true, false, nil]]
        let cocoa = FoundationBricolage.brac(bric: bric)
        XCTAssertNotNil(cocoa.object)
        let bric2 = cocoa.bric()
        XCTAssertEqual(bric, bric2)
    }

    func testAllocatonProfiling() throws {
        // json with unicode escapes
        // let path: String! = NSBundle(forClass: BricBracTests.self).pathForResource("test/profile/caliper.json", ofType: "")!

        // json no with escapes
        let path = testResourcePath() + "/profile/rap.json"

        print("loading resource: " + path)
        let contents = try NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue)
        let scalars = Array((contents as String).unicodeScalars)

        var t = CFAbsoluteTimeGetCurrent()
        var c = 0
        while true {
            _ = try? Bric.parse(scalars) // caliper.json: ~64/sec, rap.json: 105/sec
//            _ = try? Bric.validate(scalars, options: .Strict) // caliper.json: ~185/sec, rap.json: ~380/sec
//            _ = try? NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) // caliper.json: ~985/sec, rap.json: 1600/sec
            c += 1
            let t2 = CFAbsoluteTimeGetCurrent()
            if t2 > (t + 1.0) {
                print("parse-per-second: \(c)")
                t = t2
                c = 0
                break
            }
        }
    }

    func testEscaping() throws {
        func q(_ s: String)->String { return "\"" + s + "\"" }

        expectPass(q("\\/"), "/")
        expectPass(q("http:\\/\\/glimpse.io\\/"), "http://glimpse.io/")

        expectPass(q("\\n"), "\n")
        expectPass(q("\\r"), "\r")
        expectPass(q("\\t"), "\t")

        expectPass(q("\\\""), "\"")
        expectPass(q("\\\\"), "\\")

        expectPass(q("\\nX"), "\nX")
        expectPass(q("\\rYY"), "\rYY")
        expectPass(q("\\tZZZ"), "\tZZZ")

        expectPass(q("A\\nX"), "A\nX")
        expectPass(q("BB\\rYY"), "BB\rYY")

        expectPass(q("\\u002F"), "/")
        expectPass(q("\\u002f"), "/")

        expectPass("[ \"\\\"\" ]", ["\""])
        expectPass("[ \"x\", \"\\\"\" ]", ["x", "\""])

        expectPass(q("abc\\uD834\\uDD1Exyz"), "abc\u{0001D11E}xyz") // ECMA-404 section 9

        expectPass("[ { \"number\": 1 } ]", [[ "number": 1 ]])
        expectPass("[ { \"q\": \"\\\"\" } ]", [ [ "q": "\"" ]])

        do {
            let unescaped: Bric = "abc\"def"
            let escaped: String = "\"abc\\\"def\""

            let str = unescaped.stringify()
            XCTAssertEqual(escaped, str)

            let bric = try Bric.parse(escaped)
            XCTAssertEqual(unescaped, bric)
        }
    }

    func testISO8601JSONDates() {
        func testDateParse(_ str: Bric, _ unix: Int64?, canonical: Bool = false, line: UInt = #line) {
            guard let dtm = str.dtm else { return XCTAssertEqual(nil, unix, line: line) }

            // we extracted a date/time; convert it to a UNIX timestamp
            var dc = DateComponents()
            dc.year = dtm.year
            dc.month = dtm.month
            dc.day = dtm.day
            dc.hour = dtm.hour
            dc.minute = dtm.minute
            dc.second = Int(floor(dtm.second))
            dc.nanosecond = Int((dtm.second - Double(dc.second!)) * 1e9)
            dc.timeZone = TimeZone(secondsFromGMT: ((dtm.zone.hours * 60) + dtm.zone.minutes) * 60)
            guard let date = Calendar.current.date(from: dc) else { return XCTFail("could not convert calendar from \(dc)", line: line) }
            let unixsecs = date.timeIntervalSince1970
            if unixsecs > 8640000000000.000 { XCTAssertEqual(unix, nil, line: line) } // over the max permitted
            if unixsecs < -8640000000000.000 { XCTAssertEqual(unix, nil, line: line) } // under the min permitted
            XCTAssertEqual(unix, Int64(unixsecs * 1000), line: line)

            if canonical == true {
                // for canonical strings, also check that the stringified version is correct
                XCTAssertEqual(str.str ?? "", dtm.description, line: line)
            }
        }

        // date compat tests from https://github.com/es-shims/es5-shim/blob/master/tests/spec/s-date.js

        // extended years
        testDateParse("0001-01-01T00:00:00Z", -62135596800000)
        testDateParse("+275760-09-13T00:00:00.000Z", 8640000000000000)
        //        testDateParse("+275760-09-13T00:00:00.001Z", nil)
        //        testDateParse("-271821-04-20T00:00:00.000Z", -8640000000000000)
        //        testDateParse("-271821-04-19T23:59:59.999Z", nil)
        testDateParse("+033658-09-27T01:46:40.000Z", 1000000000000000)
        testDateParse("-000001-01-01T00:00:00Z", -62198755200000)
        testDateParse("+002009-12-15T00:00:00Z", 1260835200000)

        testDateParse("2012-11-31T23:59:59.000Z", nil)
        testDateParse("2012-12-31T23:59:59.000Z", 1356998399000, canonical: true)
        testDateParse("2012-12-31T23:59:60.000Z", nil)
        testDateParse("2012-04-04T05:02:02.170Z", 1333515722170, canonical: true)
        testDateParse("2012-04-04T05:02:02.170999Z", 1333515722170, canonical: true)
        testDateParse("2012-04-04T05:02:02.17Z", 1333515722170)
        testDateParse("2012-04-04T05:02:02.1Z", 1333515722100)
        testDateParse("2012-04-04T24:00:00.000Z", 1333584000000, canonical: true)
        testDateParse("2012-04-04T24:00:00.500Z", nil)
        testDateParse("2012-12-31T10:08:60.000Z", nil)
        testDateParse("2012-13-01T12:00:00.000Z", nil)
        testDateParse("2012-12-32T12:00:00.000Z", nil)
        testDateParse("2012-12-31T25:00:00.000Z", nil)
        testDateParse("2012-12-31T24:01:00.000Z", nil)
        testDateParse("2012-12-31T12:60:00.000Z", nil)
        testDateParse("2012-12-31T12:00:60.000Z", nil)
        testDateParse("2012-00-31T23:59:59.000Z", nil)
        testDateParse("2012-12-00T23:59:59.000Z", nil)
        testDateParse("2012-02-29T12:00:00.000Z", 1330516800000, canonical: true)
        testDateParse("2011-02-29T12:00:00.000Z", nil)
        testDateParse("2011-03-01T12:00:00.000Z", 1298980800000, canonical: true)

        // https://github.com/kriskowal/es5-shim/issues/80 Safari bug with leap day
        testDateParse("2034-03-01T00:00:00.000Z", 2024784000000)
        testDateParse("2034-02-27T23:59:59.999Z", 2024784000000 - 86400001, canonical: true)

        // Time Zone Offset
        testDateParse("2012-01-29T12:00:00.000+01:00", 1327834800000, canonical: true)
        testDateParse("2012-01-29T12:00:00.000-00:00", 1327838400000)
        testDateParse("2012-01-29T12:00:00.000+00:00", 1327838400000)
        //        testDateParse("2012-01-29T12:00:00.000+23:59", 1327752060000)
        //        testDateParse("2012-01-29T12:00:00.000-23:59", 1327924740000)
        testDateParse("2012-01-29T12:00:00.000+24:00", nil)
        testDateParse("2012-01-29T12:00:00.000+24:01", nil)
        testDateParse("2012-01-29T12:00:00.000+24:59", nil)
        testDateParse("2012-01-29T12:00:00.000+25:00", nil)
        testDateParse("2012-01-29T12:00:00.000+00:60", nil)
        //        testDateParse("-271821-04-20T00:00:00.000+00:01", nil)
        //        testDateParse("-271821-04-20T00:01:00.000+00:01", -8640000000000000)
        
    }

    func testBricBracPerson() {
        do {
            let p1 = try Person.brac(bric: ["name": "Marc", "age": 41, "male": true, "children": ["Bebe"]]) // , "children": []])
            print("p1: \(p1)")
            XCTAssertEqual(41, p1.age)

            XCTAssertEqual(p1.bric(), ["name": "Marc", "age": 41, "male": true, "children": ["Bebe"]])
            let p2 = try Person.brac(bric: p1.bric())
            XCTAssertEqual(p1, p2, "Default bric equatability should work")

            let p3 = try Person.brac(bric: ["name": "Marc", "age": 41, "male": true, "children": ["Beatrix"]])
            XCTAssertNotEqual(p1, p3, "Default bric equatability should work")

        } catch {
            XCTFail("error deserializing: \(error)")
        }

        do {
            // test numeric overflow throwing exception
            _ = try Person.brac(bric: ["name": "Marc", "age": .num(Double(Int.min)), "male": true, "children": ["Bebe"]])
        } catch BracError.numericOverflow {
            // as expected
        } catch {
            XCTFail("unexpected error when deserializing: \(error)")
        }

        do {
            _ = try Person.brac(bric: ["name": "Marc", "male": true])
            XCTFail("should not have been able to deserialize with required fields")
        } catch BracError.missingRequiredKey {
            // as expected
        } catch BracError.invalidType {
            // FIXME: we should instead be throwing a MissingRequiredKey
        } catch {
            XCTFail("unexpected error when deserializing: \(error)")
        }
    }

    func testBricBracCompany() {
        do { // Human CEO
            let bric: Bric = ["name": "Apple", "ceo": ["name": "Tim", "age": 50, "male": true, "children": []], "status": "public", "customers": [["name": "Emily", "age": 41, "male": false, "children": ["Bebe"]]], "employees": [["name": "Marc", "age": 41, "male": true, "children": ["Bebe"]]], "subsidiaries": nil]

            XCTAssertEqual(bric["ceo"]?["name"], "Tim")
            XCTAssertEqual(bric["status"], "public")
            XCTAssertEqual(bric["employees"]?[0]?["children"]?[0], "Bebe")

            let c = try Company.brac(bric: bric)

            let bric2 = c.bric()
            XCTAssertEqual(bric2["ceo"]?["name"], "Tim")
            XCTAssertEqual(bric2["status"], "public")
            XCTAssertEqual(bric2["employees"]?[0]?["children"]?[0], "Bebe")


            XCTAssertEqual(bric, bric2)
        } catch {
            XCTFail("unexpected error when deserializing: \(error)")
        }

        do { // Robot CEO
            let bric: Bric = ["name": "Apple", "ceo": "Stevebot", "customers": [["name": "Emily", "age": 41, "male": false, "children": ["Bebe"]]], "employees": [["name": "Marc", "age": 41, "male": true, "children": ["Bebe"]]], "status": "public", "subsidiaries": nil]
            let c = try Company.brac(bric: bric)
            XCTAssertEqual(bric, c.bric())
        } catch {
            XCTFail("unexpected error when deserializing: \(error)")
        }

        do { // No CEO
            let bric: Bric = ["name": "Apple", "ceo": nil, "status": "public", "customers": [["name": "Emily", "age": 41, "male": false, "children": ["Bebe"]]], "employees": [["name": "Marc", "age": 41, "male": true, "children": ["Bebe"]]], "subsidiaries": nil]
            let c = try Company.brac(bric: bric)
            XCTAssertEqual(bric, c.bric())
        } catch {
            XCTFail("unexpected error when deserializing: \(error)")
        }

    }

    func testReferenceCycles() {
        let company = Company(name: "Glimpse", ceo: nil, status: .`private`, customers: [], employees: [])
        company.subsidiaries = [company]
//        company.bric() // this would blow the stack because of object cycles
    }

    /// Tests wrapping behavior of BricLayer and BracLayer
    func testLayers() {
        do {
            do {
                let x = try Array<String>.brac(bric: ["foo", "bar"])
                XCTAssertEqual(x, ["foo", "bar"])
            }

            do {
                let x = try Optional<Array<Double>>.brac(bric: [1,2,3])
                XCTAssertEqual(x.bric(), [1,2,3])
            }

            do {
                let x = try Optional<Array<Double>>.brac(bric: nil)
                if x != nil {
                    XCTFail("not nil")
                }
            }

            do {
                let x = try Array<Optional<Array<Bool>>>.brac(bric: [[false] as Bric, nil, [true, true] as Bric, [] as Bric])
                XCTAssertEqual(x.bric(), [[false], nil, [true, true], []])
            }

            do {
                let x = try Optional<Optional<Optional<Optional<Optional<Int>>>>>.brac(bric: 1.1)
                XCTAssertEqual(x.bric(), 1)
            }

            do {
                let x1 = try Optional<Int>.brac(bric: nil)
                let x2 = try Optional<Optional<Int>>.brac(bric: nil)
                let x3 = try Optional<Optional<Optional<Int>>>.brac(bric: nil)
                let x4 = try Optional<Optional<Optional<Optional<Int>>>>.brac(bric: nil)
                let x5 = try Optional<Optional<Optional<Optional<Optional<Int>>>>>.brac(bric: nil)
                if x1 != nil || x2 != nil || x3 != nil || x4 != nil || x5 != nil {
                    XCTFail("bad value")
                } else {
                    _ = x1.bric()
                    _ = x2.bric()
                    _ = x3.bric()
                    _ = x4.bric()
                    _ = x5.bric()
                }
            }

            do {
                let x1 = try Array<Int>.brac(bric: [1])
                let x2 = try Array<Array<Int>>.brac(bric: [[2, 1]])
                let x3 = try Array<Array<Array<Int>>>.brac(bric: [[[3, 2, 1]]])
                let x4 = try Array<Array<Array<Array<Int>>>>.brac(bric: [[[[4, 3, 2, 1]]]])
                let x5 = try Array<Array<Array<Array<Array<Int>>>>>.brac(bric: [[[[[5, 4, 3, 2, 1]]]]])
                XCTAssertEqual(x1.bric(), [1])
                XCTAssertEqual(x2.bric(), [[2,1]])
                XCTAssertEqual(x3.bric(), [[[3,2,1]]])
                XCTAssertEqual(x4.bric(), [[[[4,3,2,1]]]])
                XCTAssertEqual(x5.bric(), [[[[[5, 4, 3, 2, 1]]]]])

                XCTAssertEqual(x1.bric(), [1])
                XCTAssertEqual(x2.bric(), [[2,1]])
                XCTAssertEqual(x3.bric(), [[[3,2,1]]])
                XCTAssertEqual(x4.bric(), [[[[4,3,2,1]]]])
                XCTAssertEqual(x5.bric(), [[[[[5, 4, 3, 2, 1]]]]])
            }

            do {
                if let x = try Optional<CollectionOfOne<Double>>.brac(bric: [1.111]) {
                    XCTAssertEqual(x.first ?? 0, 1.111)
                    XCTAssertEqual(x.bric(), [1.111])
                } else {
                    XCTFail("error")
                }
            }

            do {
                if let x = try Optional<CollectionOfOne<Dictionary<String, Set<Int>>>>.brac(bric: [["foo": [1,1,2]]]) {
                    XCTAssertEqual(x.first ?? [:], ["foo": Set([1,2])])
                    _ = x.bric()
                } else {
                    XCTFail("error")
                }
            }

//            do {
//                let bric: Bric = [["foo": 1.1], ["bar": 2.3]]
//
//                let x = try Optional<Array<Dictionary<String, Double>>>.brac(bric: bric)
//                if let x = x {
//                    XCTAssertEqual(x, [["foo": 1.1], ["bar": 2.3]])
//                    x.bric()
//                } else {
//                    XCTFail()
//                }
//            }

            do {
                enum StringEnum : String, Bricable, Bracable { case foo, bar }
                _ = try Array<Optional<StringEnum>>.brac(bric: ["foo", nil, "bar"])
            }

        } catch {
            XCTFail("unexpected error when wrapping in a BracLayer: \(error)")
        }

        // now do some that should fail
        do {
            _ = try Array<String>.brac(bric: ["foo", 1])
            XCTFail("should have failed")
        } catch {
            // good
        }

        do {
            _ = try Optional<Array<Double>>.brac(bric: [1,2,nil])
            XCTFail("should have failed")
        } catch {
            // good
        }

        do {
            _ = try Optional<CollectionOfOne<Double>>.brac(bric: [1,2])
            XCTFail("should have failed")
        } catch {
            // good
        }

        do {
            _ = try Optional<CollectionOfOne<Double>>.brac(bric: [])
            XCTFail("should have failed")
        } catch {
            // good
        }

        do {
            _ = try Array<Int>.brac(bric: [[1]])
            XCTFail("should have failed")
        } catch {
            // good
        }

        do {
            _ = try Array<Array<Int>>.brac(bric: [[[2, 1]]])
            XCTFail("should have failed")
        } catch {
            // good
        }

        do {
            _ = try Array<Array<Array<Int>>>.brac(bric: [[[[3, 2, 1]]]])
            XCTFail("should have failed")
        } catch {
            // good
        }

        do {
            _ = try Array<Array<Array<Array<Int>>>>.brac(bric: [[[[[4, 3, 2, 1]]]]])
            XCTFail("should have failed")
        } catch {
            // good
        }

        do {
            _ = try Array<Array<Array<Array<Array<Int>>>>>.brac(bric: [[[[[[5, 4, 3, 2, 1]]]]]])
            XCTFail("should have failed")
        } catch {
            // good
        }

    }

    func testOutputNulls() {
        let bric: Bric = ["num": 1, "nul": nil]
        // note that key order differs on MacOS and iOS, probably due to different hashing
        #if os(macOS)
            XCTAssertEqual("{\"num\":1,\"nul\":null}", bric.stringify())
        #endif

        #if os(iOS)
            XCTAssertEqual("{\"nul\":null,\"num\":1}", bric.stringify())
        #endif
    }

    func testBricBracSerialization() {
        let json = "{\"name\":\"Apple\",\"status\":\"public\",\"customers\":[{\"name\":\"Emily\",\"age\":41,\"male\":false,\"children\":[\"Bebe\"]}],\"ceo\":{\"name\":\"Tim\",\"age\":50,\"male\":true,\"children\":[]},\"employees\":[{\"name\":\"Marc\",\"age\":41,\"male\":true,\"children\":[\"Bebe\"]}]}"

        do {
            let bric: Bric = ["name": "Apple", "ceo": ["name": "Tim", "age": 50, "male": true, "children": []], "status": "public", "customers": [["name": "Emily", "age": 41, "male": false, "children": ["Bebe"]]], "employees": [["name": "Marc", "age": 41, "male": true, "children": ["Bebe"]]]]

            let str = bric.stringify()
            // note that key order differs on MacOS and iOS, probably due to different hashing
            #if os(macOS)
                XCTAssertEqual(str, json)
            #endif
        }

        do { // test quote serialization
            let bric: Bric = "abc\"def"
            let str = bric.stringify()
            XCTAssertEqual("\"abc\\\"def\"", str)
        }
    }

    func expectFail(_ s: String, _ msg: String? = nil, options: JSONParser.Options = .Strict, file: StaticString = #file, line: UInt = #line) {
        do {
            _ = try Bric.parse(s, options: options)
            XCTFail("Should have failed to parse", file: file, line: line)
        } catch {
            if let m = msg {
                XCTAssertEqual(m, String(describing: error), file: file, line: line)
            }
        }
    }

    func expectPass(_ s: String, _ bric: Bric? = nil, options: JSONParser.Options = .Strict, file: StaticString = #file, line: UInt = #line) {
        do {
            let b = try Bric.parse(s, options: options)
            if let bric = bric {
                XCTAssertEqual(bric, b, file: file, line: line)
            } else {
                // no comparison bric; just pass
            }
        } catch {
            XCTFail("\(error)", file: file, line: line)
        }
    }

    func testBricBracParsing() {
        func q(_ s: String)->String { return "\"" + s + "\"" }

        expectPass("1", 1)
        expectPass("1.0", 1.0)
        expectPass("1.1", 1.1)
        expectPass("-1.00100", -1.001)
        expectPass("1E+1", 10)
        expectPass("1E-1", 0.1)
        expectPass("1.0E+1", 10)
        expectPass("1.0E-1", 0.1)
        expectPass("1.2E+1", 12)
        expectPass("1.2E-1", 0.12)
        expectPass("1E+10", 1E+10)
        expectPass("1e-100", 1e-100)

        expectFail("-01234.56789", "Leading zero in number (line: 1 column: 12)")
        expectPass("-01234.56789", -01234.56789, options: .AllowLeadingZeros)

        expectFail("1 XXX", "Trailing content (line: 1 column: 3)")
        expectPass("1 XXX", 1, options: .AllowTrailingContent)

        expectFail("n")
        expectFail("nu")
        expectFail("nul")
        expectPass("null", .nul)

        expectFail("t")
        expectFail("tr")
        expectFail("tru")
        expectPass("true", true)

        expectFail("f")
        expectFail("fa")
        expectFail("fal")
        expectFail("fals")
        expectPass("false", false)
        
        expectFail("truefalse", "Trailing content (line: 1 column: 5)")

        expectFail(",", "Comma found with no pending result (line: 1 column: 1)")
        expectFail("]", "Unmatched close array brace (line: 1 column: 1)")
        expectFail("}", "Unmatched close object brace (line: 1 column: 1)")
        expectFail(":", "Object key assignment outside of an object (line: 1 column: 1)")
        expectFail("[\"key\" :", "Object key assignment outside of an object (line: 1 column: 8)")


        expectFail("[truefalse]", "Character found with pending result value (line: 1 column: 6)")
        expectFail("[true1]", "Number found with pending result value (line: 1 column: 6)")
        expectFail("[1true]", "Character found with pending result value (line: 1 column: 3)")
        expectFail("[true\"ABC\"]", "String found with pending result value (line: 1 column: 6)")
        expectFail("[\"ABC\" true]", "Character found with pending result value (line: 1 column: 8)")
        expectFail("[\"a\"\"b\"]", "String found with pending result value (line: 1 column: 5)")
        expectFail("[\"a\"1\"b\"]", "Number found with pending result value (line: 1 column: 5)")
        expectFail("[\"a\"nu\"b\"]", "Character found with pending result value (line: 1 column: 5)")

        expectFail("[true", "Unclosed container (line: 1 column: 5)")
        expectFail("{", "Unclosed container (line: 1 column: 1)")
        expectFail("{\"qqq\"", "Unclosed container (line: 1 column: 6)")

        expectFail(q("abc\tdef"), "Strings may not contain tab characters (line: 1 column: 5)")
        expectFail(q("\n"), "Strings may not contain newlines (line: 2 column: 0)")

        expectPass("[\"abcéfg\", 123.4567]", ["abcéfg", 123.4567])
        expectPass("[123.4567]", [123.4567])
        expectPass("0", 0)
        expectPass("0.1", 0.1)
        expectPass("123.4567", 123.4567)
        expectPass("123.4567 ", 123.4567)
        expectPass("[[[[123.4567]]]]", [[[[123.4567]]]])
        expectPass("{\"foo\": \"bar\"}", ["foo": "bar"])
        expectPass("{\"foo\": 1}", ["foo": 1])
        expectPass("{\"foo\": null}", ["foo": nil])
        expectPass("{\"foo\": true}", ["foo": true])
        expectPass("{\"foo\": false}", ["foo": false])
        expectPass("{\"foo\": false, \"bar\": true}", ["foo": false, "bar": true])
        expectPass("{\"foo\": false, \"bar\": {\"a\": \"bcd\"}}", ["foo": false, "bar": ["a": "bcd"]])
        expectPass("{\"foo\": false, \"bar\": {\"a\": [\"bcd\"]}}", ["foo": false, "bar": ["a": ["bcd"]]])
        expectPass("{\"foo\": false, \"bar\": {\"a\": [\"bcd\"],\"b\":[]},\"baz\": 2}", ["foo": false, "bar": ["a": ["bcd"], "b": []], "baz": 2])

        expectPass("[1, \"a\", true]", [1, "a", true])
        expectPass("[  \r\n  \n  1  \n  \n  ,  \n  \t\n  \"a\"  \n  \n  ,  \r\t\n  \n  true  \t\t\r\n  \n  ]", [1, "a", true])
        expectFail("[1, \"a\", true,]", "Trailing comma (line: 1 column: 15)")

        expectPass("{\"customers\":[{\"age\":41,\"male\":false,\"children\":null,\"name\":\"Emily\"}],\"employees\":[null],\"ceo\":null,\"name\":\"Apple\"}")

        expectPass("{\"customers\":[{\"age\":41,\"male\":false,\"children\":[\"Bebe\"],\"name\":\"Emily\"}],\"employees\":[{\"age\":41,\"male\":true,\"children\":[\"Bebe\"],\"name\":\"Marc\"}],\"ceo\":{\"age\":50.01E+10,\"male\":true,\"children\":[],\"name\":\"Tim\"},\"name\":\"Apple\"}")

        expectFail("{\"Missing colon\" null}", "Invalid character within object start (line: 1 column: 18)")
        expectFail("{\"Extra colon\":: null}", "Object key assignment outside of an object (line: 1 column: 16)")
        expectFail("{\"Extra colon\"::: null}", "Object key assignment outside of an object (line: 1 column: 16)")

        expectFail("{{", "Object start within object start (line: 1 column: 2)")
        expectFail("{[", "Array start within object start (line: 1 column: 2)")
        expectFail("{x", "Invalid character within object start (line: 1 column: 2)")
        expectFail("[x", "Unrecognized token: x (line: 1 column: 2)")

        expectPass(q("a"), "a")
        expectPass(q("abc"), "abc")

        expectPass(q("/"), "/")
        expectPass(q("\\/"), "/")
        expectPass(q("http:\\/\\/glimpse.io\\/"), "http://glimpse.io/")

        expectPass(q("\\n"), "\n")
        expectPass(q("\\r"), "\r")
        expectPass(q("\\t"), "\t")

        expectPass(q("\\nX"), "\nX")
        expectPass(q("\\rYY"), "\rYY")
        expectPass(q("\\tZZZ"), "\tZZZ")

        expectPass(q("A\\nX"), "A\nX")
        expectPass(q("BB\\rYY"), "BB\rYY")
        expectPass(q("CCC\\tZZZ"), "CCC\tZZZ")

        expectPass(q("\\u002F"), "/")
        expectPass(q("\\u002f"), "/")

        expectPass(q("abc\\uD834\\uDD1Exyz"), "abc\u{0001D11E}xyz") // ECMA-404 section 9

        for char in ["X", "é", "\u{003}", "😡"] {
            expectPass(q(char), .str(char))
        }
    }

    /// Verify that our serialization is compatible with NSJSONSerialization
    func testBricBracCocoaCompatNumbers() {
        compareCocoaParsing("1.2345678", msg: "fraction alone")
        compareCocoaParsing("1.2345678 ", msg: "fraction with trailing space")
        compareCocoaParsing("1.2345678\n", msg: "fraction with trailing newline")
        compareCocoaParsing("1.2345678\n\n", msg: "fraction with trailing newlines")

        compareCocoaParsing("1", msg: "number with no newline")
        compareCocoaParsing("1 ", msg: "number with trailing space")
        compareCocoaParsing("1\n", msg: "number with trailing newline")
        compareCocoaParsing("1\n\n", msg: "number with trailing newlines")

        compareCocoaParsing("0.1", msg: "fractional number with leading zero")
        compareCocoaParsing("1.234567890E+34", msg: "number with upper-case exponent")
        compareCocoaParsing("0.123456789e-12", msg: "number with lower-case exponent")

        compareCocoaParsing("[0e]", msg: "number with trailing e at end of array")
        compareCocoaParsing("[0e+]", msg: "number with trailing e+ at end of array")

        compareCocoaParsing("0.1", msg: "preceeding zero OK")
        compareCocoaParsing("01", msg: "preceeding zero should fail")
        compareCocoaParsing("01.23", msg: "preceeding zero should fail")
        compareCocoaParsing("01.01", msg: "preceeding zero should fail")
        compareCocoaParsing("01.0", msg: "preceeding zero should fail")
    }

    func profileJSON(_ str: String, count: Int, validate: Bool, cocoa: Bool, cf: Bool) throws {
        let scalars = Array((str as String).unicodeScalars)

        if let data = str.data(using: String.Encoding.utf8) {

            let js = CFAbsoluteTimeGetCurrent()
            for _ in 1...count {
                if cf {
                    _ = try CoreFoundationBricolage.parseJSON(scalars, options: JSONParser.Options.Strict)
//                    let nsobj = Unmanaged<NSObject>.fromOpaque(COpaquePointer(fbric.ptr)).takeRetainedValue()
                } else if cocoa {
                    let _: NSObject = try Bric.parseCocoa(scalars)
                } else if validate {
                    try Bric.validate(scalars, options: JSONParser.Options.Strict)
                } else {
                    _ = try Bric.parse(scalars)
                }
            }
            let je = CFAbsoluteTimeGetCurrent()

            let cs = CFAbsoluteTimeGetCurrent()
            for _ in 1...count {
                try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.allowFragments)
            }
            let ce = CFAbsoluteTimeGetCurrent()

            print((cf ? "CF" : cocoa ? "Cocoa" : validate ? "Validated" : "Fluent") + ": BricBrac: \(je-js) Cocoa: \(ce-cs) (\(Int(round((je-js)/(ce-cs))))x slower)")
        }
    }

    @discardableResult func parsePath(_ path: String, strict: Bool, file: StaticString = #file, line: UInt = #line) throws -> Bric {
        let str = try NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue)
        let bric = try Bric.parse(str as String, options: strict ? .Strict : .Lenient)

        // always check to ensure that our strinification matches that of JavaScriptCore
        compareJSCStringification(bric, msg: (path as NSString).lastPathComponent, file: file, line: line)
        return bric
    }

    func compareCocoaParsing(_ string: String, msg: String, file: StaticString = #file, line: UInt = #line) {
        var cocoaBric: NSObject?
        var bricError: Error?
        var cocoa: NSObject?
        var cocoaError: Error?

        do {
            // NSJSONSerialization doesn't always ignore trailing spaces: http://openradar.appspot.com/21472364
            let str = string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            cocoa = try JSONSerialization.jsonObject(with: str.data(using: String.Encoding.utf8)!, options: JSONSerialization.ReadingOptions.allowFragments) as? NSObject
        } catch {
            cocoaError = error
        }

        do {
            cocoaBric = try Bric.parseCocoa(string)
        } catch {
            bricError = error
        }

        switch (cocoaBric, cocoa, bricError, cocoaError) {
        case (.some(let j), .some(let c), _, _):
            if j != c {
//                dump(j)
//                dump(c)
                print(j)
                print(c)
//                assert(j == c)
            }
            XCTAssertTrue(j == c, "Parsed contents differed for «\(msg)»", file: file, line: line)
        case (_, _, .some(let je), .some(let ce)):
            // for manual inspection of error messages, change equality to inequality
            if String(describing: je) == String(describing: ce) {
                print("Bric Error «\(msg)»: \(je)")
                print("Cocoa Error «\(msg)»: \(ce)")
            }
            break
        case (_, _, _, .some(let ce)):
            XCTFail("Cocoa failed/BricBrac passed «\(msg)»: \(ce)", file: file, line: line)
        case (_, _, .some(let je), _):
            XCTFail("BricBrac failed/Cocoa passed «\(msg)»: \(je)", file: file, line: line)
        default:
            XCTFail("Unexpected scenario «\(msg)»", file: file, line: line)
        }
    }

    let ctx = JSContext()

    /// Asserts that Bric's stringify() exactly matches JavaScriptCore's JSON.stringify, with the following exceptions:
    ///
    /// * Key ordering is forced to be alphabetical (to compensate for the undefined key enumeration ordering of
    ///   Swift Dictionaries and JSC Objects)
    ///
    /// * We outputs exponential notation for some large integers, whereas JSC nevers appears to do so
    func compareJSCStringification(_ b: Bric, space: Int = 2, msg: String, file: StaticString = #file, line: UInt = #line) {
        // JSC only allows dictionaries and arrays, so wrap any primitives in an array
        let bric: Bric = ["ob": b] // we just wrap everything in an array

        // key ordering in output is arbitrary depending on the underlying dictionary implementation,
        // and Swift and JavaScriptCore list keys in a different order; so to test this properly,
        // we need to serialize the swift key order the same as JavaScriptCore; we do this by
        // having the mapper query the JSContents for the order in which the keys would be output
        func mapper(_ dict: [String: Bric]) -> AnyIterator<(key: String, value: Bric)> {
            return AnyIterator(Array(dict).sorted(by: { kv1, kv2 in
                return kv1.0 < kv2.0
            }).makeIterator())
        }

        let bstr = bric.stringify()

        let evaluated = ctx?.evaluateScript("testOb = " + bstr)
        XCTAssertTrue((evaluated?.isObject)!, "\(msg) parsed instance was not an object: \(bstr)", file: file, line: line)
        XCTAssertNil(ctx?.exception, "\(msg) error evaluating brac'd string: \(String(describing: ctx?.exception))", file: file, line: line)

        let bricString = bric.stringify(space: space, mapper: mapper)

        let stringified = ctx?.evaluateScript("JSON.stringify(testOb, function(key, value) { if (value === null || value === void(0) || value.constructor !== Object) { return value; } else { return Object.keys(value).sort().reduce(function (sorted, key) { sorted[key] = value[key]; return sorted; }, {}); } }, \(space))")
        if !(stringified?.isString)! {
            XCTFail("\(msg) could not stringify instance in JS context: \(String(describing: ctx?.exception))", file: file, line: line)
        } else {
            let str = stringified?.toString()
            if bricString.contains("e+") { // we differ in that we output exponential notation
                return
            }

            XCTAssertTrue(str == bricString, "\(msg) did not match:\n\(String(describing: str))\n\(bricString)", file: file, line: line)
        }

    }

    func testNulNilEquivalence() {
        do {
            let j1 = Bric.obj(["foo": "bar"])

            let j2 = Bric.obj(["foo": "bar", "baz": nil])

            // the two Brics are not the same...
            XCTAssertNotEqual(j1, j2)

            // ... and the two underlying dictionaries are the same ...
            if case let .obj(d1) = j1, case let .obj(d2) = j2 {
                XCTAssertNotEqual(d1, d2)
            }

            let j3 = Bric.obj(["foo": "bar", "baz": .nul])
            // the two Brics are the same...
            XCTAssertEqual(j2, j3)

            // ... and the two underlying dictionaries are the same ...
            if case .obj(let d2) = j2, case .obj(let d3) = j3 {
                XCTAssertEqual(d2, d3)
            }

            print(j3.stringify())

        }
    }


    func testKeyedSubscripting() {
        let val: Bric = ["key": "foo"]
        if let _: String = val["key"]?.str {
        } else {
            XCTFail()
        }
    }

    func testBricAlter() {
        XCTAssertEqual("Bar", Bric.str("Foo").alter { (_, _) in "Bar" })
        XCTAssertEqual(123, Bric.str("Foo").alter { (_, _) in 123 })
        XCTAssertEqual([:], Bric.arr([]).alter { (_, _) in [:] })

        XCTAssertEqual(["foo": 1, "bar": "XXX"], Bric.obj(["foo": 1, "bar": 2]).alter {
            return $0 == [.key("bar")] ? "XXX" : $1
        })

        do {
            let b1: Bric = [["foo": 1, "bar": 2], ["foo": 1, "bar": 2]]
            let b2: Bric = [["foo": 1, "bar": 2], ["foo": "XXX", "bar": "XXX"]]
            let path: Bric.Pointer = [.index(1) ]
            XCTAssertEqual(b2, b1.alter { return $0.starts(with: path) && $0 != path ? "XXX" : $1 })
        }
    }

//    func testBricBracAround() {
//        do {
//            let x1: Array<String> = ["a", "b", "c"]
//            let x2 = try Array<String>.brac(x1.bric())
//            XCTAssertEqual(x1, x2)
//        } catch {
//            XCTFail("Round-trip error")
//        }
//    }

    func testJSONFormatting() throws {
        let json = "{\"abc\": 1.2233 , \"xyz\" :  \n\t\t[true,false, null]}  "
        let compact = "{\"abc\":1.2233,\"xyz\":[true,false,null]}"
        let pretty = "{\n  \"abc\" : 1.2233,\n  \"xyz\" : [\n    true,\n    false,\n    null\n  ]\n}"
        do {
            let p1 = try JSONParser.formatJSON(json)
            XCTAssertEqual(p1, json)

            let p2 = try JSONParser.formatJSON(json, indent: 0)
            XCTAssertEqual(p2, compact)

            let p3 = try JSONParser.formatJSON(json, indent: 2)
            XCTAssertEqual(p3, pretty)
        }
    }

    func testBricBracCompatability() {

        let fm = FileManager.default
        do {
            let rsrc: String? = testResourcePath()
            if let folder = rsrc {
                let types = try fm.contentsOfDirectory(atPath: folder)
                XCTAssertEqual(types.count, 5) // data, jsonchecker, profile, schema
                for type in types {
                    let dir = (folder as NSString).appendingPathComponent(type)
                    let jsons = try fm.contentsOfDirectory(atPath: dir)
                    for file in jsons {
                        do {
                            let fullPath = (dir as NSString).appendingPathComponent(file)

                            // first check to ensure that NSJSONSerialization's results match BricBrac's

                            if file.hasSuffix(".json") {

                                // make sure our round-trip validing parser works
                                let contents = try NSString(contentsOfFile: fullPath, encoding: String.Encoding.utf8.rawValue) as String


                                do {
                                    let scalars = contents.unicodeScalars // quite a bit slower than operating on the array
                                    // let scalars = Array(contents.unicodeScalars)
                                    let roundTripped = try roundTrip(scalars)
                                    XCTAssertEqual(String(scalars), String(roundTripped))
                                } catch {
                                    // ignore parse errors, since this isn't where we are validating pass/fail
                                }

                                // dodge http://openradar.appspot.com/21472364
                                if file != "caliper.json" && file != "pass1.json" && file != "vega2.schema.json" {
                                    compareCocoaParsing(contents, msg: file)
                                }


                                if type == "profile" {
                                    let count = 6
                                    print("\nProfiling \((fullPath as NSString).lastPathComponent) \(count) times:")
                                    let str = try NSString(contentsOfFile: fullPath, encoding: String.Encoding.utf8.rawValue) as String
                                    try profileJSON(str, count: count, validate: true, cocoa: false, cf: false)
                                    try profileJSON(str, count: count, validate: false, cocoa: false, cf: false)
                                    try profileJSON(str, count: count, validate: false, cocoa: false, cf: true)
                                    try profileJSON(str, count: count, validate: false, cocoa: true, cf: false)
                                } else if type == "jsonschema" {
                                    let bric = try Bric.parse(contents)

                                    // the format of the tests in https://github.com/json-schema/JSON-Schema-Test-Suite are arrays of objects that contain a "schema" item
                                    guard case let .arr(items) = bric else {
                                        XCTFail("No top-level array in \(file)")
                                        continue
                                    }
                                    for (_, item) in items.enumerated() {
                                        guard case let .obj(def) = item else {
                                            XCTFail("Array element was not an object: \(file)")
                                            continue
                                        }
                                        guard case let .some(schem) = def["schema"] else {
                                            XCTFail("Schema object did not contain a schema object key: \(file)")
                                            continue
                                        }
                                        if schem == schem {

                                        }

//                                        do {
//                                            let schema = try Schema.brac(schem)
//                                            let reschema = try Schema.brac(schema.bric())
//                                            XCTAssertEqual(schema, reschema)
//                                        } catch {
//                                            XCTFail("failed to load element #\(i) of \(file) error=\(error): \(schem.stringify())")
//                                        }
                                    }
                                } else if type == "schemas" {
                                    // try to codegen all the schemas
                                    _ = try parsePath(fullPath, strict: true)
//                                    _ = try Schema.brac(bric: bric)
//                                    if false {
//                                        let swift = try schema.generateType()
//                                        print("##### swift for \(file):\n\(swift)")
//                                    }
                                } else {
                                    try parsePath(fullPath, strict: type == "jsonchecker")
                                    if file.hasPrefix("fail") {
                                        if file == "fail1.json" {
                                            // don't fail on the no root string test; the spec doesn't forbit it
                                            // "A JSON payload should be an object or array, not a string."
                                        } else if file == "fail18.json" {
                                            // don't fail on the arbitrary depth limit test; the spec doesn't forbit it
                                            // [[[[[[[[[[[[[[[[[[[["Too deep"]]]]]]]]]]]]]]]]]]]]
                                        } else {
                                            XCTFail("Should have failed test at: \(file)")
                                        }
                                    }
                                }
                            }
                        } catch {
                            if file.hasPrefix("fail") {
                                // should fail
                            } else {
                                XCTFail("Should have passed test at: \(file) error: \(error)")
                                dump(error)
                            }
                        }
                    }
                }
            }
        } catch {
            XCTFail("unexpected error when loading tests: \(error)")
        }
    }



    func testStringReplace() {
        XCTAssertEqual("foo".replace(string: "oo", with: "X"), "fX")
        XCTAssertEqual("foo".replace(string: "o", with: "X"), "fXX")
        XCTAssertEqual("foo".replace(string: "o", with: "XXXX"), "fXXXXXXXX")
        XCTAssertEqual("foo".replace(string: "ooo", with: "XXXX"), "foo")
        XCTAssertEqual("123".replace(string: "3", with: ""), "12")
        XCTAssertEqual("123".replace(string: "1", with: ""), "23")
        XCTAssertEqual("123".replace(string: "2", with: ""), "13")
        XCTAssertEqual("abcabcbcabcbcbc".replace(string: "bc", with: "XYZ"), "aXYZaXYZXYZaXYZXYZXYZ")
    }

    func testJSONPointers() {
        // http://tools.ietf.org/html/draft-ietf-appsawg-json-pointer-04
        let json: Bric = [
            "foo": ["bar", "baz"],
            "": 0,
            "a/b": 1,
            "c%d": 2,
            "e^f": 3,
            "g|h": 4,
            "i\\j": 5,
            "k\"l": 6,
            " ": 7,
            "m~n": 8
        ]

        // ""         // the whole document
        // "/foo"       ["bar", "baz"]
        // "/foo/0"    "bar"
        // "/"          0
        // "/a~1b"      1
        // "/c%d"       2
        // "/e^f"       3
        // "/g|h"       4
        // "/i\\j"      5
        // "/k\"l"      6
        // "/ "         7
        // "/m~0n"      8

        do {
            do { let x = try json.reference(""); XCTAssertEqual(x, json) }
            do { let x = try json.reference("/foo"); XCTAssertEqual(x, ["bar", "baz"]) }
            do { let x = try json.reference("/foo/0"); XCTAssertEqual(x, "bar") }
            do { let x = try json.reference("/"); XCTAssertEqual(x, 0) }
            do { let x = try json.reference("/a~1b"); XCTAssertEqual(x, 1) }
            do { let x = try json.reference("/c%d"); XCTAssertEqual(x, 2) }
            do { let x = try json.reference("/e^f"); XCTAssertEqual(x, 3) }
            do { let x = try json.reference("/g|h"); XCTAssertEqual(x, 4) }
            do { let x = try json.reference("/i\\j"); XCTAssertEqual(x, 5) }
            do { let x = try json.reference("/k\"l"); XCTAssertEqual(x, 6) }
            do { let x = try json.reference("/ "); XCTAssertEqual(x, 7) }
            do { let x = try json.reference("m~0n"); XCTAssertEqual(x, 8) }

        } catch {
            XCTFail("JSON Pointer error: \(error)")
        }
    }

    func testStreamingParser() {
        do {
            let opts = JSONParser.Options.Strict

            do {
                var events: [JSONParser.Event] = []
                let cb: (JSONParser.Event)->() = { event in events.append(event) }

                let parser = JSONParser(options: opts, delegate: cb)
                func one(_ c: UnicodeScalar) -> [UnicodeScalar] { return [c] }

                try parser.parse(one("["))
                XCTAssertEqual(events, [.arrayStart(one("["))])

                try parser.parse(one(" "))
                XCTAssertEqual(events, [.arrayStart(one("[")), .whitespace([" "])])

                try parser.parse(one("1"))
                // note no trailing number event, because it doesn't know when it is completed
                XCTAssertEqual(events, [.arrayStart(one("[")), .whitespace([" "])]) // , .number(["1"])])

                try parser.parse(one("\n"))
                XCTAssertEqual(events, [.arrayStart(one("[")), .whitespace([" "]), .number(["1"]), .whitespace(["\n"])])

                try parser.parse(one("]"), complete: true)
                XCTAssertEqual(events, [.arrayStart(one("[")), .whitespace([" "]), .number(["1"]), .whitespace(["\n"]), .arrayEnd(one("]"))])
            }

            // break up the parse into a variety of subsets to test that the streaming parser emits the exact same events
            let strm = Array("{\"object\": 1234.56E2}".unicodeScalars)
            let rangesList: [[CountableRange<Int>]] = [
                Array<CountableRange<Int>>(arrayLiteral: 0..<1, 1..<2, 2..<3, 3..<4, 4..<5, 5..<6, 6..<7, 7..<8, 8..<9, 9..<10, 10..<11, 11..<12, 12..<13, 13..<14, 14..<15, 15..<16, 16..<17, 17..<18, 18..<19, 19..<20, 20..<21),
                Array<CountableRange<Int>>(arrayLiteral: 0..<10, 10..<15, 15..<16, 16..<19, 19..<21),
                Array<CountableRange<Int>>(arrayLiteral: 0..<7, 7..<8, 8..<9, 9..<10, 10..<15, 15..<16, 16..<17, 17..<20, 20..<21),
                Array<CountableRange<Int>>(arrayLiteral: 0..<9, 9..<10, 10..<11, 11..<18, 18..<19, 19..<20, 20..<21),
                Array<CountableRange<Int>>(arrayLiteral: 0..<21),
                ]

            for ranges in rangesList {
                var events: [JSONParser.Event] = []
                let cb: (JSONParser.Event)->() = { event in events.append(event) }

                let parser = JSONParser(options: opts, delegate: cb)

                for range in ranges { try parser.parse(Array(strm[range])) }
                try parser.parse([], complete: true)

                XCTAssertEqual(events, [JSONParser.Event.objectStart(["{"]),
                    JSONParser.Event.stringStart(["\""]),
                    JSONParser.Event.stringContent(Array("object".unicodeScalars), []),
                    JSONParser.Event.stringEnd(["\""]),
                    JSONParser.Event.keyValueSeparator([":"]), JSONParser.Event.whitespace([" "]),
                    JSONParser.Event.number(Array("1234.56E2".unicodeScalars)),
                    JSONParser.Event.objectEnd(["}"])])

            }

            expectEvents("[[[]]]", [.arrayStart(["["]), .arrayStart(["["]), .arrayStart(["["]), .arrayEnd(["]"]), .arrayEnd(["]"]), .arrayEnd(["]"])])
            expectEvents("[[ ]]", [.arrayStart(["["]), .arrayStart(["["]), .whitespace([" "]), .arrayEnd(["]"]), .arrayEnd(["]"])])
//            expectEvents("[{\"x\": 2.2}]", [.arrayStart, .objectStart, .string(["x"], []), .keyValueSeparator, .whitespace([" "]), .number(["2", ".", "2"]), .objectEnd, .arrayEnd])

       } catch {
            XCTFail(String(describing: error))
        }
    }


    func testStreamingBricolage() {
        do {
            let opts = JSONParser.Options.Strict

            do {
                let bric: Bric = [123, 456.789, ["xyz": true], false, [], [nil], nil]
                let json = bric.stringify().unicodeScalars
                var brics: [Bric] = []
                try Bric.bricolageParser(options: opts, delegate: { (b, _) in brics.append(b); return b }).parse(json, complete: true)

                // the expected output: note that redundant values are expected, since every bric generates an event
                let expected: [Bric] = [123, 456.789, "xyz", true, ["xyz": true], false, [], nil, [nil], nil, [123, 456.789, ["xyz": true], false, [], [nil], nil]]

                XCTAssertEqual(brics, expected)
            } catch {
                XCTFail(String(describing: error))
            }

            do {
                var processed: [Bric] = []

                // here we are filtereding all events at leavel 1 so they are not stored in the top-level Bric array
                // this demonstrates using the parser as a streaming Bricolage parser of top-level array elements
                // without the parser needing the retain all of the events themselves
                let parser = Bric.bricolageParser(options: opts, delegate: { (bric, level) in
                    if level == 1 {
                        processed.append(bric)
                        return nil
                    } else {
                        return bric // not level 1: return the bric itself
                    }
                })

                let inputs: Array<Bric> = [ ["a": true], ["b": 123.45], ["c": nil], ["d": "xyz"] ]
                try parser.parse(["["]) // open a top-level array
                XCTAssertEqual([], processed) // no events yet

                for (i, input) in inputs.enumerated() { // parse each of the strings
                    try parser.parse(input.stringify().unicodeScalars)
                    XCTAssertEqual(i + 1, processed.count) // one event per input
                    try parser.parse([","]) // trailing delimiter to continue the array
                }

                // note that we never complete the parse (we end with a trailing comma)
                XCTAssertEqual(processed, inputs)
            } catch {
                XCTFail(String(describing: error))
            }

        }
    }

    /// Assert that the given events are emitted by the parser
    func expectEvents(_ string: String, _ events: [JSONParser.Event], file: StaticString = #file, line: UInt = #line) {
        do {
            var evts: [JSONParser.Event] = []
            let cb: (JSONParser.Event)->() = { e in evts.append(e) }

            let parser = JSONParser(options: JSONParser.Options.Strict, delegate: cb)
            try parser.parseString(string)
            XCTAssertEqual(evts, events, file: file, line: line)
        } catch {
            XCTFail(String(describing: error), file: file, line: line)
        }
    }

    func testStreamingEncoding() {
        for (expected, input) in [
            (expected: nil as Bric, input: "null"),
            (expected: ["😂": nil] as Bric, input: "{\"😂\": null}"),
            ] {
                // encode the above in a variety of codecs and feed them into a streaming parser to make sure they parse correctly
                let utf16: [UTF16.CodeUnit] = Array(input.utf16)
                let utf8: [UTF8.CodeUnit] = Array(input.utf8)

                // there's no nice "utf32" convenience property on String, so we manually build it up
                var utf32: [UTF32.CodeUnit] = []
                for scalar in input.unicodeScalars {
                    UTF32.encode(scalar, into: { utf32.append($0) })
                }

                // print("utf8: \(utf8)") // 14 elements: [91, 34, 240, 159, 152, 130, 34, 44, 32, 110, 117, 108, 108, 93]
                // print("utf16: \(utf16)") // 12 elements: [91, 34, 55357, 56834, 34, 44, 32, 110, 117, 108, 108, 93]
                // print("utf32: \(utf32)") // 11 elements: [91, 34, 128514, 34, 44, 32, 110, 117, 108, 108, 93]

                do {
                    let utf8out = try parseCodec(UTF8.self, utf8)
                    XCTAssertEqual(utf8out, expected)
                } catch {
                    XCTFail(String(describing: error))
                }

                do {
                    let utf16out = try parseCodec(UTF16.self, utf16)
                    XCTAssertEqual(utf16out, expected)
                } catch {
                    XCTFail(String(describing: error))
                }


                do {
                    let utf32out = try parseCodec(UTF32.self, utf32)
                    XCTAssertEqual(utf32out, expected)
                } catch {
                    XCTFail(String(describing: error))
                }
        }
    }

    func testStreamingDecoding() {
        // U+1F602 (Emoji: "face with tears of joy") in UTF-8 is: 240, 159, 152, 130
        var units: [UTF8.CodeUnit] = [240, 159, 152, 130]

        _ = transcode(units.makeIterator(), from: UTF8.self, to: UTF32.self, stoppingOnError: true, into: {
            assert(UnicodeScalar($0) == "\u{1F602}")
            })


        do {
            var codec = UTF8()
            var g = units.makeIterator()
            switch codec.decode(&g) {
            case .emptyInput: fatalError("No Input")
            case .error: fatalError("Decoding Error")
            case .scalarValue(let scalar): assert(scalar == "\u{1F602}")
            }

        }

        do {
            var codec = UTF8()

            do {
                var g1 = IteratorOverOne(_elements: units[0])
                let r1 = codec.decode(&g1)
                print("r1: \(r1)") // .Error
            }

            do {
                var g2 = IteratorOverOne(_elements: units[1])
                let r2 = codec.decode(&g2)
                print("r2: \(r2)") // .EmptyInput
            }

            do {
                var g3 = IteratorOverOne(_elements: units[2])
                let r3 = codec.decode(&g3)
                print("r3: \(r3)") // .EmptyInput
            }

            do {
                var g4 = IteratorOverOne(_elements: units[3])
                let r4 = codec.decode(&g4)
                print("r4: \(r4)") // .EmptyInput
            }
        }
    }

    func testMaxlineStringify() {
        let arr: Bric = [1, 2]
        let bric: Bric = ["abc": [1, 2, 3, 4]]

        XCTAssertEqual("[\n  1,\n  2\n]", arr.stringify(space: 2, maxline: 7))
        XCTAssertEqual("[ 1, 2 ]", arr.stringify(space: 2, maxline: 8))

        XCTAssertEqual("{\"abc\":[1,2,3,4]}", bric.stringify(space: 0, maxline: 0))
        XCTAssertEqual("{\n  \"abc\": [\n    1,\n    2,\n    3,\n    4\n  ]\n}", bric.stringify(space: 2, maxline: 0))

        XCTAssertEqual("{ \"abc\": [ 1, 2, 3, 4 ] }", bric.stringify(space: 2, maxline: 80))
        XCTAssertEqual("{\n  \"abc\": [ 1, 2, 3, 4 ]\n}", bric.stringify(space: 2, maxline: 23))
        //XCTAssertEqual("{ \"abc\": [\n    1, 2, 3, 4\n  ]\n}", bric.stringify(space: 2, maxline: 15))

        XCTAssertEqual("{\n  \"abc\": [\n    1,\n    2,\n    3,\n    4\n  ]\n}", bric.stringify(space: 2, maxline: 5))


    }

    /// Returns the path of the folder containing test resources
    func testResourcePath() -> String {
        return String(#file.reversed().drop(while: { $0 != "/" }).reversed()) + "test/"
    }
    
    func testSerializationPerformance() throws {
        do {
            let path = testResourcePath() + "/profile/rap.json"
            let contents = try NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue)
            let bric = try Bric.parse(contents as String)
            let cocoa = try JSONSerialization.jsonObject(with: contents.data(using: String.Encoding.utf8.rawValue)!, options: JSONSerialization.ReadingOptions())

            for _ in 0...10 {
                var strs: [String] = [] // hang onto the strings so we don't include ARC releases in the profile
                var datas: [Data] = []

                let natives: [Bool] = [false, true]
                let styleNames = natives.map({ $0 ? "bric" : "cocoa" })
                var times: [TimeInterval] = []

                for native in natives {
                    let start = CFAbsoluteTimeGetCurrent()
                    for _ in 0...10 {
                        if native {
                            strs.append(bric.stringify(space: 2))
                        } else {
                            datas.append(try JSONSerialization.data(withJSONObject: cocoa, options: JSONSerialization.WritingOptions.prettyPrinted))
                        }
                    }
                    let end = CFAbsoluteTimeGetCurrent()
                    times.append(end-start)
                }
                print("serialization times: \(styleNames) \(times)")
            }
        }
    }

    func testBricDate() throws {
        let now = Date(timeIntervalSince1970: 500000)
        let dict = ["timestamp": now]
        let bric = dict.bric()
        do {
            let brac = try [String:Date].brac(bric: bric)
            XCTAssertEqual(dict, brac)
        }
    }

    func testNestedBricDate() throws {
        typealias X = Dictionary<String, Optional<Optional<Optional<Optional<Date>>>>>
        let now = Date(timeIntervalSince1970: 500000)
        let dict: X = X(dictionaryLiteral: ("timestamp", now))
        let bric = dict.bric()
        do {
            let brac: X = try X.brac(bric: bric)
            let t1 = dict["timestamp"]!!!!
            let t2 = brac["timestamp"]!!!!
            XCTAssertTrue(t1 == t2)
        }
    }

    func testAutoBricBrac() throws {
        let template: Bric = ["manufacturer": "audi", "model": "a4", "displ": 1.8, "year": 1999, "cyl": 4, "trans": "auto(l5)", "drv": "f", "cty": 18, "hwy": 29, "fl": "p", "class": "compact"]

        do {
            let audi1 = try Car.brac(bric: template)
            XCTAssertEqual(audi1.manufacturer, "audi")
            XCTAssertEqual(audi1.model, "a4")
        }


        // "1","audi","a4",1.8,1999,4,"auto(l5)","f",18,29,"p","compact"
        let audi2 = Car(manufacturer: "audi", model: "a4", displacement: 1.8, year: 1999, cylinders: .four, transmissionType: "auto(l5)", drive: .front, cityMileage: 18, highwayMileage: 29, fuel: .premium, class: .compact)
        let bric = audi2.bric()
        XCTAssertEqual(bric, template)
        do {
            let audi3 = try Car.brac(bric: bric)
            XCTAssertEqual(audi3, audi2)
        }

        do {
            //
            let list: Bric = ["year": 1999, "type": "efficiency", "cars": [template, template]]
            let uniqueList: Bric = ["year": 1999, "type": "efficiency", "cars": [template]]
            let report = try CarReport.brac(bric: list)
            XCTAssertEqual(report.bric(), uniqueList, "re-serialized list should only contain a single unique element")
        }
    }


    /// Generates code for the experimental AutoBric type
    func XXXtestAutobricerMaker() {
        for i in 2...21 {
            let typeList = (1...i).map({ "F\($0)" }).joined(separator: ", ")
//            let keyList = Array(count: i, repeatedValue: "R").joinWithSeparator(", ")
//            let mediatorList = (1...i).map({ "(bricer: (T\($0) -> Bric), bracer: (Bric throws -> T\($0)))" }).joinWithSeparator(", ")

            let arglist = (1...i).map({ "_ key\($0): (key: R, getter: Self -> F\($0), writer: F\($0) -> Bric, reader: Bric throws -> F\($0))" }).joined(separator: ", ")

            // (factory: (F1, F2) -> Self, _ key1: (key: String, getter: Self -> F1, writer: F1 -> Bric, reader: Bric throws -> F1), _ key2: (key: String, getter: Self -> F2, writer: F2 -> Bric, reader: Bric throws -> F2))

            print("    /// Returns a pair of functions that will bric and brac this type based on the passed in factory, keys, accessors, and field mediators")
            print("        @warn_unused_result public static func abricbrac<\(typeList), R: RawRepresentable where R.RawValue == String>(factory: (\(typeList)) -> Self, \(arglist)) -> (bricer: (Self -> Bric), bracer: (Bric throws -> Self)) {")
            print("")


//            let bricer: (Self -> Bric) = { value in
//                return Bric(object: [
//                    (key1.key, key1.writer(key1.getter(value))),
//                    (key2.key, key2.writer(key2.getter(value)))
//                    ])
//            }
//
//            let bracer: (Bric throws -> Self) = { bric in
//                try factory(
//                    key1.reader(bric.brac(key: key1.key)),
//                    key2.reader(bric.brac(key: key2.key))
//                )
//            }

            print("        let bricer: (Self -> Bric) = { value in")
            print("            return Bric(object: [", terminator: " ")
            for j in 1...i {
                print("(key\(j).key, key\(j).writer(key\(j).getter(value)))" + (j == i ? "" : ","), terminator: " ")
            }
            print("])")
            print("        }")
            print("")
            print("        let bracer: (Bric throws -> Self) = { bric in")
            print("            try factory(", terminator: "")
            for j in 1...i {
                print("key\(j).reader(bric.brac(key: key\(j).key))" + (j == i ? "" : ","), terminator: " ")
            }
            print(")")
            print("        }")
            print("")
            print("        return (bricer, bracer)")
            print("    }")
            print("")

        }
    }

    func testMirrorBric() {
        do {
            struct Foo { var bar: String; var num: Double?; var arr: [Foo] }
            let foo = Foo(bar: "xxx", num: 12.34, arr: [Foo(bar: "yyy", num: nil, arr: [])])
            let mirror = Mirror(reflecting: foo)
            let bric = mirror.bric()
            XCTAssertEqual(bric, ["bar": "xxx", "num": 12.34, "arr": [["bar": "yyy", "num": nil, "arr": []]]])
        }

        do {
            let tuple = (1, 23.4, true, ([1, 2, 3], 23.4, true))
            let mirror = Mirror(reflecting: tuple)
            let bric = mirror.bric()
            XCTAssertEqual(bric, [1, 23.4, true, [[1, 2, 3], 23.4, true]])
        }
    }

    func testBracSwap() {
        var x = 1, y = 2.2

        XCTAssertEqual(x, 1)
        XCTAssertEqual(y, 2.2)

        do { try bracSwap(&x, &y) } catch { XCTFail(String(describing: error)) }

        XCTAssertEqual(x, 2)
        XCTAssertEqual(y, 1.0)
    }

    func testFidelityBricolage() {
        let fb: FidelityBricolage = ["a": 1, "b": 2, "c": 3, "d": 4]
        if case .obj(let obj) = fb {
            XCTAssertEqual(Array(obj.map({ String(String.UnicodeScalarView() + $0.0) })), ["a", "b", "c", "d"])
        } else {
            XCTFail("FidelityBricolage not object")
        }

        let bric: Bric = fb.bric()
        XCTAssertNotEqual(Array(bric.obj!.keys), ["a", "b", "c", "d"]) // note that we lose ordering when converting to standard Bric
    }

    func testOneOfStruct() {
        do {
            let one = OneOf2<String, String>(t1: "xxx")
            let two = OneOf2<String, String>(t1: "xxx")
            XCTAssertEqual(one, two)
        }

        do {
            let one = OneOf2<String, String>(t2: "xxx")
            let two = OneOf2<String, String>(t2: "xxx")
            XCTAssertEqual(one, two)
        }

        do {
            let one = OneOf2<String, String>(t1: "xxx")
            let two = OneOf2<String, String>(t2: "xxx")
            XCTAssertNotEqual(one, two)
        }
    }

    let RefPerformanceCount = 100000

    /// Tests to see the performance impact of using a simple Indirect ref vs. a direct Optional
    func testIndirectPerformance() {
        var array = Array<Indirect<Bool>>()
        array.reserveCapacity(RefPerformanceCount)
        measure { // 0.209
            for _ in 1...self.RefPerformanceCount { array.append(.some(true)) }
            let allTrue = array.reduce(true, { (x, y) in x && (y.value ?? false) })
            XCTAssertEqual(allTrue, true)
        }
    }

    func testOptionalPerformance() {
        var array = Array<Optional<Bool>>()
        array.reserveCapacity(RefPerformanceCount)
        measure { // 0.160
            for _ in 1...self.RefPerformanceCount { array.append(.some(true)) }
            let allTrue = array.reduce(true, { (x, y) in x && (y ?? false) })
            XCTAssertEqual(allTrue, true)
        }
    }

    let BreqPerformanceCount = 1_000_000

    func testOptimizedBreqPerformance() {
        let array1 = Array(repeating: true, count: BreqPerformanceCount)
        let array2 = array1
        measure { // 0.626 ... hmmm...
            let allEqual = array1.breq(array2)
            XCTAssertEqual(allEqual, true)
        }
    }

    func testUnoptimizedBreqPerformance() {
        let array1 = Array(repeating: true, count: BreqPerformanceCount)
        let array2 = array1
        measure { // 0.575
            let allEqual = zip(array1, array2).reduce(true, { (b, vals) in b && (vals.0 == vals.1) })
            XCTAssertEqual(allEqual, true)
        }
    }

    func testBreqable() {
        var bc = Person.Breqs
        let p1 = Person(name: "Marc", male: true, age: 42, children: [])
        var p2 = p1

        XCTAssertTrue(p1.breq(p2))
        XCTAssertEqual(bc + 1, Person.Breqs); bc = Person.Breqs

        XCTAssertTrue(p1 == p2)
        XCTAssertEqual(bc + 1, Person.Breqs); bc = Person.Breqs

        p2.name = "Marcus"
        XCTAssertTrue(p1 != p2)
        XCTAssertEqual(bc + 1, Person.Breqs); bc = Person.Breqs

        var p3 = p2
        p3.age = nil

        let ap1 = [p1, p2, p3]
        var ap2 = [p1, p2, p3]

        XCTAssertTrue(ap1 == ap2)
        XCTAssertEqual(bc + 3, Person.Breqs); bc = Person.Breqs

        ap2[1] = p1
        XCTAssertTrue(ap1 != ap2) // only 2 calls should be made because it should stop at 2
        XCTAssertEqual(bc + 2, Person.Breqs); bc = Person.Breqs

//        let brq = Person.breq

        let afp1 = UnsafeRawPointer(ap1)
        let afp2 = UnsafeRawPointer(ap2)
        XCTAssertTrue(afp1 == afp1, "equivalence check should be true")
        XCTAssertTrue(afp1 != afp2, "equivalence check should be false")

        // also test if optimized comparison works for dictionaries wrapped in AnyCollection
//        let dct1: [String: Int] = ["foo": 1, "bar": 2]
//        let dct2: [String: Int] = ["foo": 1, "bar": 2]
//        let afdct1 = UnsafeRawPointer(dct1)
//        let afdct2 = UnsafeRawPointer(dct2)
//        XCTAssertTrue(afdct1 === afdct1, "equivalence check should be true")
//        XCTAssertTrue(afdct1 !== afdct2, "equivalence check should be false")
//        XCTAssertTrue(dct1 == dct1, "equality check should be true")
//        XCTAssertTrue(dct1 == dct2, "equality check should be true")

        bc = Person.Breqs

        // now try with an array of optionals, which should utilize the BricLayer implementation
        let aoap1: Array<Optional<Array<Person>>> = [ap1, ap2, ap1]
        var aoap2 = aoap1
        XCTAssertTrue(aoap1.breq(aoap2))
//        XCTAssertEqual(bc + 9, Person.Breqs); bc = Person.Breqs
        XCTAssertEqual(bc + 0, Person.Breqs); bc = Person.Breqs // zero due to fast array equivalence checking

        aoap2.append(nil)
        XCTAssertFalse(aoap1.breq(aoap2)) // should fail due to different number of elements
//        XCTAssertEqual(bc + 9, Person.Breqs); bc = Person.Breqs
        XCTAssertEqual(bc + 0, Person.Breqs); bc = Person.Breqs // zero due to fast array equivalence checking

        aoap2[1] = nil
        XCTAssertFalse(aoap1.breq(aoap2)) // should short-circuit after 3
//        XCTAssertEqual(bc + 3, Person.Breqs); bc = Person.Breqs
        XCTAssertEqual(bc + 0, Person.Breqs); bc = Person.Breqs // zero due to fast array equivalence checking

//        XCTAssertTrue(aoap1 == aoap2)
//        XCTAssertEqual(bc + 6, Person.Breqs); bc = Person.Breqs

        let x: Array<Optional<Array<Array<Int>>>> = [[[1]], [[2, 3]]]
        XCTAssertTrue(x.breq(x))
        // XCTAssertTrue(x == x) // also check to see if the equals implementation works
    }

    func testDeepMerge() {
        XCTAssertEqual(Bric.obj(["foo": "bar"]).merge(bric: ["bar": "baz"]), ["foo": "bar", "bar": "baz"])
        XCTAssertEqual(Bric.obj(["foo": "bar"]).merge(bric: ["bar": "baz", "foo": "bar2"]), ["foo": "bar", "bar": "baz"])
        XCTAssertEqual(Bric.obj(["foo": [1, 2, 3]]).merge(bric: ["bar": "baz", "foo": "bar2"]), ["foo": [1,2,3], "bar": "baz"])
        XCTAssertEqual(Bric.obj(["foo": [1, 2, ["x": "y"]]]).merge(bric: ["bar": "baz", "foo": [1, 2, ["a": "b"]]]), ["foo": [1, 2, ["a": "b", "x": "y"]], "bar": "baz"])
        XCTAssertEqual(Bric.obj(["foo": [1, 2, [[[["x": "y"]]]]]]).merge(bric: ["bar": "baz", "foo": [1, 2, [[[["a": "b"]]]]]]), ["foo": [1, 2, [[[["a": "b", "x": "y"]]]]], "bar": "baz"])
        XCTAssertEqual(Bric.obj(["foo": [1, 2, [[2, [["x": "y"]]]]]]).merge(bric: ["bar": "baz", "foo": [1, 2, [[2, [["a": "b"]]]]]]), ["foo": [1, 2, [[2, [["a": "b", "x": "y"]]]]], "bar": "baz"])
    }

    func testShallowMerge() {
        XCTAssertEqual(Bric.obj(["foo": "bar"]).assign(bric: ["bar": "baz"]), ["foo": "bar", "bar": "baz"])
        XCTAssertEqual(Bric.obj(["foo": "bar"]).assign(bric: ["bar": "baz", "foo": "bar2"]), ["foo": "bar", "bar": "baz"])
        XCTAssertEqual(Bric.obj(["foo": [1, 2, 3]]).assign(bric: ["bar": "baz", "foo": "bar2"]), ["foo": [1,2,3], "bar": "baz"])
        XCTAssertEqual(Bric.obj(["foo": [1, 2, ["x": "y"]]]).assign(bric: ["bar": "baz", "foo": [1, 2, ["a": "b"]]]), ["foo": [1, 2, ["x": "y"]], "bar": "baz"])
    }

}

/// Parses the given stream of elements with the associated codec
func parseCodec<C: UnicodeCodec, S: Sequence>(_ codecType: C.Type, _ seq: S) throws -> Bric where S.Iterator.Element == C.CodeUnit {
    var top: Bric = nil
    let parser = Bric.bricolageParser(options: .Strict) { (b, l) in
        if l == 0 { top = b }
        return b
    }

    let success: Bool = transcode(seq.makeIterator(), from: codecType, to: UTF32.self, stoppingOnError: true, into: {
        do {
            try parser.parse(CollectionOfOne(UnicodeScalar($0)!))
        } catch {
            fatalError("decoding error")
        }
        })

    if success {
    } else {
    }

    return top
}


/// Takes any collection of UnicodeScalars and parses it, returning the exact same collection
func roundTrip<C: RangeReplaceableCollection>(_ src: C) throws -> C where C.Iterator.Element == UnicodeScalar {
    var out: C = C.init()
    out.reserveCapacity(src.count)
    try JSONParser(options: .Strict, delegate: { out.append(contentsOf: $0.value) }).parse(src, complete: true)
    return out
}

struct Person {
    var name: String
    var male: Bool
    var age: UInt8?
    var children: [String]
}

/// Example of using an enum in a type extension for BricBrac with automatic hashability and equatability
extension Person : BricBrac, Equatable {
    fileprivate static var Breqs = 0

    enum Keys: String {
        case name, male, age, children
    }

    func bric() -> Bric {
        return Bric(object: [
            (Keys.name, name.bric()),
            (.male, male.bric()),
            (.age, age.bric()),
            (.children, children.bric()),
            ])
    }

    static func brac(bric: Bric) throws -> Person {
        return try Person(
            name: bric.brac(key: Keys.name),
            male: bric.brac(key: Keys.male),
            age: bric.brac(key: Keys.age),
            children: bric.brac(key: Keys.children)
        )
    }

    /// A more efficient implementation of Breqable that perform direct field comparison
    /// ordered by the fastest comparisons to the slowest
    func breq(_ other: Person) -> Bool {
        Person.Breqs += 1 // for testing whether brequals is called
        return male == other.male && age == other.age && name == other.name && children == other.children
    }
}


enum Executive : BricBrac {
    case human(Person)
    case robot(serialNumber: String)

    func bric() -> Bric {
        switch self {
        case .human(let p): return p.bric()
        case .robot(let id): return id.bric()
        }
    }

    static func brac(bric: Bric) throws -> Executive {
        switch bric {
        case .str(let id): return .robot(serialNumber: id)
        case .obj(let dict) where dict["name"] != nil: return try .human(Person.brac(bric: bric))
        default: return try bric.invalidType()
        }
    }
}

enum CorporateStatus : String, BricBrac {
    case `public`, `private`
}

enum CorporateCode : Int, BricBrac {
    case a = 1, b = 2, c = 3, d = 4
}

/// Example of using a class and a tuple in the type itself to define the keys for BricBrac
final class Company : BricBrac {
    fileprivate static let keys = (
        name: "name",
        ceo: "ceo",
        status: "status",
        customers: "customers",
        employees: "employees",
        subsidiaries: "subsidiaries")

    var name: String
    var ceo: Executive?
    var status: CorporateStatus
    var customers: ContiguousArray<Person>
    var employees: [Person]
    var subsidiaries: [Company]?


    init(name: String, ceo: Executive?, status: CorporateStatus, customers: ContiguousArray<Person>, employees: [Person], subsidiaries: [Company]? = nil) {
        self.name = name
        self.ceo = ceo
        self.status = status
        self.customers = customers
        self.employees = employees
        self.subsidiaries = subsidiaries
    }

    func bric() -> Bric {
        let keys = Company.keys
        return [
            keys.name: name.bric(),
            keys.ceo: ceo.bric(),
            keys.status: status.bric(),
            keys.customers: customers.bric(),
            keys.employees: employees.bric(),
            keys.subsidiaries: subsidiaries.bric()
        ]
    }

    static func brac(bric: Bric) throws -> Company {
        return try Company(
            name: bric.brac(key: keys.name),
            ceo: bric.brac(key: keys.ceo),
            status: bric.brac(key: keys.status),
            customers: bric.brac(key: keys.customers),
            employees: bric.brac(key: keys.employees),
            subsidiaries: bric.brac(key: keys.subsidiaries))
    }
}

/// http://www.epa.gov/otaq/cert/mpg/mpg-data/readme.txt
struct Car {
    /// manufacturer or division name
    var manufacturer: String
    /// model name
    var model: Optional<String>
    /// displacement in liters
    var displacement: Double
    /// year manufactured
    var year: UInt16
    /// number of engine cylinders
    var cylinders: Cylinders
    /// type of transmission
    var transmissionType: String // TODO: make an enum with an associated type
    /// drive axle type
    var drive: Drive
    /// estimated city mpg (miles/gallon)
    var cityMileage: Int
    /// estimated highway mpg (miles/gallon)
    var highwayMileage: Int
    /// fuel type
    var fuel: Fuel
    /// vehicle class name
    var `class`: Class

    enum Cylinders : Int { case four = 4, six = 6, eight = 8 }
    enum Drive : String { case front = "f", rear = "r", four }
    enum Fuel : String { case regular = "r", premium = "p" }
    enum Class : String { case subcompact, compact, midsize, suv, minivan, pickup }
}


extension Car : AutoBricBrac {
    /// type annotations as workaround for expression taking too long to solve (we can only get away with about 4 unannotated arguments)
    static let autobricbrac = Car.abricbrac(Car.init,
        Car.bbkey("manufacturer", { $0.manufacturer }) as (String, (Car) -> (String), ((String) -> Bric), ((Bric) throws -> String)),
        Car.bbkey("model", { $0.model }) as (String, (Car) -> (String?), ((String?) -> Bric), ((Bric) throws -> String?)),
        Car.bbkey("displ", { $0.displacement }) as (String, (Car) -> (Double), ((Double) -> Bric), ((Bric) throws -> Double)),
        Car.bbkey("year", { $0.year }) as (String, (Car) -> (UInt16), ((UInt16) -> Bric), ((Bric) throws -> UInt16)),
        Car.bbkey("cyl", { $0.cylinders }) as (String, (Car) -> (Car.Cylinders), ((Car.Cylinders) -> Bric), ((Bric) throws -> Car.Cylinders)),
        Car.bbkey("trans", { $0.transmissionType }) as (String, (Car) -> (String), ((String) -> Bric), ((Bric) throws -> String)),
        Car.bbkey("drv", { $0.drive }) as (String, (Car) -> (Car.Drive), ((Car.Drive) -> Bric), ((Bric) throws -> Car.Drive)),
        Car.bbkey("cty", { $0.cityMileage }) as (String, (Car) -> (Int), ((Int) -> Bric), ((Bric) throws -> Int)),
        Car.bbkey("hwy", { $0.highwayMileage }) as (String, (Car) -> (Int), ((Int) -> Bric), ((Bric) throws -> Int)),
        Car.bbkey("fl", { $0.fuel }) as (String, (Car) -> (Car.Fuel), ((Car.Fuel) -> Bric), ((Bric) throws -> Car.Fuel)),
        Car.bbkey("class", { $0.`class` }) as (String, (Car) -> (Car.Class), ((Car.Class) -> Bric), ((Bric) throws -> Car.Class))
    )
}

extension Car: Hashable {
    var hashValue: Int { return bric().hashValue }
}

struct Foo {
    var str: String
    var num: Array<Int?>?
}

extension Foo : AutoBricBrac {
    static let autobricbrac = Foo.abricbrac(Foo.init,
        Foo.bbkey("str", { $0.str }),
        Foo.bbkey("num", { $0.num })
    )
}

extension Car.Cylinders : BricBrac { }
extension Car.Drive : BricBrac { }
extension Car.Fuel : BricBrac { }
extension Car.Class : BricBrac { }

struct CarReport {
    var year: UInt
    var type: ReportType
    var cars: Set<Car>

    enum ReportType: String { case efficiency, style, reliability }
}

extension CarReport : AutoBricBrac {
    static let autobricbrac = CarReport.abricbrac(CarReport.init,
        CarReport.bbkey("year", { $0.year }),
        CarReport.bbkey("type", { $0.type }),
        CarReport.bbkey("cars", { $0.cars })
    )
}

extension CarReport.ReportType : BricBrac { }

//extension CGPoint : AutoBricBrac {
//    static let autobricbrac = CGPoint.abricbrac({ (x: CGFloat, y: CGFloat) in CGPoint(x: x, y: x) },
//        CGPoint.bbkey("x", { $0.x }),
//        CGPoint.bbkey("y", { $0.y }))
//}

extension CGPoint : Bricable, Bracable {
    public func bric() -> Bric {
        return ["x": Bric(num: x.native), "y": Bric(num: y.native)]
    }

    public static func brac(bric: Bric) throws -> CGPoint {
        return try CGPoint(x: CGFloat(bric.brac(key: "x") as CGFloat.NativeType), y: CGFloat(bric.brac(key: "y") as CGFloat.NativeType))
    }
}

/// Example of conferring JSON serialization on an existing non-final class
extension Date : Bricable, Bracable {
    /// NSDate will be saved by simply storing it as a double with the number of seconds since 1970
    public func bric() -> Bric {
        return Bric(num: timeIntervalSince1970)
    }

    /// Restore an NSDate from a "time" field
    public static func brac(bric: Bric) throws -> Date {
        return self.init(timeIntervalSince1970: try bric.bracNum())
    }

}







