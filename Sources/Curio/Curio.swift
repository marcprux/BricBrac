//
//  Curio.swift
//  BricBrac
//
//  Created by Marc Prud'hommeaux on 6/30/15.
//  Copyright © 2010-2020 io.glimpse. All rights reserved.
//

/// A JSON Schema processor that emits Swift code using the Bric-a-Brac framework for marshalling and unmarshalling.
///
/// Current shortcomings:
/// • "anyOf" schema type values cannot prevent that all their tuple elements not be set to nil
///
/// TODO:
/// • hide Indirect in private fields and make public Optional getters/setters
public struct Curio {

    /// The swift version to generate
    public var swiftVersion = 4.2

    /// whether to generate codable implementations for each type
    public var generateCodable = true

    /// whether to cause `CodingKeys` to conform to `Idenfiable`
    public var generateIdentifiable = true

    /// The name of a typealias from the `CodingKeys` implementation to the owning `Codable`
    public var codingOwner: CodeTypeName? = "CodingOwner"

    /// whether to cause `CodingKeys` to embed a `keyDescription` field
    public var keyDescriptionMethod = true

    /// Whether to generate a compact representation with type shorthand and string enum types names reduced
    public var compact = true

    /// whether to generate structs or classes (classes are faster to compiler for large models)
    public var generateValueTypes = true

    /// whether to generate equatable functions for each type
    public var generateEquals = true

    /// whether to generate hashable functions for each type
    public var generateHashable = true

    /// Whether to output union types as a typealias to a BricBrac.OneOf<T1, T2, ...> enum
    public var useOneOfEnums = true

    /// Whether to output sum types as a typealias to a BricBrac.AllOf<T1, T2, ...> enum
    public var useAllOfEnums = true

    /// Whether to output optional sum types as a typealias to a BricBrac.AnyOf<T1, T2, ...> enum
    public var useAnyOfEnums = true

    /// Whether AnyOf elements should be treated as OneOf elements
    public var anyOfAsOneOf = false

    /// Whether to generate `KeyedCodable` conformance
    public var generateKeyedCodable = true

    /// the number of properties beyond which Optional types should instead be Indirect; this is needed beause
    /// a struct that contains many other stucts can make very large compilation units and take a very long
    /// time to compile
    /// This isn't as much of an issue now that OneOfNType enums are indirect; the vega-lite schema is 7M with indirectCountThreshold=9 and 13M with indirectCountThreshold=99
    /// Also, if indirectCountThreshold is to be used, we need to synthesize the CodingKeys macro again
    public var indirectCountThreshold = 99

    /// The prefix for private internal indirect implementations
    public var indirectPrefix = "_"

    /// Whether enums that are generated should be marked as `indirect`
    public var indirectEnums = true

    /// The suffic for a OneOf choice enum
    public var oneOfSuffix = "Choice"

    /// The suffic for a AllOf choice enum
    public var allOfSuffix = "Sum"

    /// The suffic for a AnyOf choice enum
    public var anyOfSuffix = "Some"

    /// The suffix for a case operation
    public var caseSuffix = "Case"

    public var accessor: ([CodeTypeName]) -> (CodeAccess) = { _ in .`public` }
    public var renamer: ([CodeTypeName], String) -> (CodeTypeName?) = { (parents, id) in nil }

    /// The name of a centralized enum for all top-level ty
    public var registryTypeName: String? = nil

    /// The name of a centralized conformance type to synthesize and conform to (in additional to the default equatable, codable, etc.)
    public var conformances: [CodeProtocol] = []

    /// The list of type names to exclude from the generates file
    public var excludes: Set<CodeTypeName> = []

    /// The list of type aliases that will wrap around their aliased types
    public var encapsulate: [CodeTypeName: CodeExternalType] = [:]

    /// Override individual property types
    public var propertyTypeOverrides: [CodeTypeName: CodeTypeName] = [:]

    /// Manual specification of property indirects
    public var propertyIndirects: Set<CodeTypeName> = []

    /// The case of the generated enums
    public var enumCase: EnumCase = .lower

    public enum EnumCase { case upper, lower }

    /// special prefixes to trim (adheres to the convention that top-level types go in the "defintions" level)
    public var trimPrefixes = ["#/definitions/", "#/defs/"]

    /// The suffix to append to generated types
    public var typeSuffix = ""

    /// Whether to gather identical types and promote them to a top level upon reificiation (helps with reducing the number of parochical string constants and local oneofs)
    public var promoteIdenticalTypes = true

    public var propOrdering: ([CodeTypeName], String)->(Array<String>?) = { (parents, id) in nil }

    /// The protocols all our types will adopt
    var standardAdoptions: [CodeProtocol] {
        var protos: [CodeProtocol] = []
        if generateEquals { protos.append(.equatable) }
        if generateHashable { protos.append(.hashable) }
        if generateCodable { protos.append(.codable) }
        protos += conformances
        return protos
    }

    public init() {
    }

    enum CodegenErrors : Error, CustomDebugStringConvertible {
        case typeArrayNotSupported
        case illegalDefaultType
        case defaultValueNotInStringEnum
        case nonStringEnumsNotSupported // TODO
        case tupleTypeingNotSupported // TODO
        case complexTypesNotAllowedInMultiType
        case illegalState(String)
        case unsupported(String)
        indirect case illegalProperty(Schema)
        case compileError(String)
        case emptyEnum

        var debugDescription : String {
            switch self {
            case .typeArrayNotSupported: return "TypeArrayNotSupported"
            case .illegalDefaultType: return "IllegalDefaultType"
            case .defaultValueNotInStringEnum: return "DefaultValueNotInStringEnum"
            case .nonStringEnumsNotSupported: return "NonStringEnumsNotSupported"
            case .tupleTypeingNotSupported: return "TupleTypeingNotSupported"
            case .complexTypesNotAllowedInMultiType: return "ComplexTypesNotAllowedInMultiType"
            case .illegalState(let x): return "IllegalState(\(x))"
            case .unsupported(let x): return "Unsupported(\(x))"
            case .illegalProperty(let x): return "IllegalProperty(\(x))"
            case .compileError(let x): return "CompileError(\(x))"
            case .emptyEnum: return "EmptyEnum"
            }
        }
    }

    /// Alphabetical characters
    static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    /// “Identifiers begin with an uppercase or lowercase letter A through Z, an underscore (_), a noncombining alphanumeric Unicode character in the Basic Multilingual Plane, or a character outside the Basic Multilingual Plane that isn’t in a Private Use Area.”
    static let nameStart = Set((alphabet.uppercased() + "_" + alphabet.lowercased()))

    /// “After the first character, digits and combining Unicode characters are also allowed.”
    static let nameBody = Set(Array(nameStart) + "0123456789")

    func propName(_ parents: [CodeTypeName], _ id: String, arg: Bool = false) -> CodePropName {
        if let pname = renamer(parents, id) {
            return pname
        }

        // enums can't have a prop named "init", since it will conflict with the constructor name
        var idx = id // id == "init" ? "initx" : id

        while let first = idx.first, !Curio.nameStart.contains(first) {
            idx = String(idx.dropFirst())
        }

        // swift version 2.2+ allow unescaped keywords as argument names: https://github.com/apple/swift-evolution/blob/master/proposals/0001-keywords-as-argument-labels.md
        let escape = arg ? idx.isSwiftReservedArg() : idx.isSwiftKeyword()
        if escape {
            idx = "`" + idx + "`"
        }

        // replace all illegal characters with nothing
        for ichar in ["-"] {
            idx = idx.replace(string: ichar, with: "")
        }
        return idx
    }

    func unescape(_ name: String) -> String {
        if name.hasPrefix("`") && name.hasSuffix("`") && name.count >= 2 {
            return String(name[name.index(after: name.startIndex)..<name.index(before: name.endIndex)])
        } else {
            return name
        }
    }

    func sanitizeString(_ fromName: String, capitalize: Bool = true) -> String {
        let nm: String
        // if the name is just a number, then try to use the spelling of the number
        if Double(fromName)?.description == fromName {
            nm = "n" + fromName
        } else {
            // we need to swap out "[]" for "Array" before we start stripping out illegal characters
            // because there might be some schema type like: ConditionalAxisProperty<(number[]|undefined|null)
            nm = fromName.replacingOccurrences(of: "[]", with: "Array")
        }

        var name = ""

        var capnext = capitalize
        for c in nm {
            let validCharacters = name.isEmpty ? Curio.nameStart : Curio.nameBody
            if c == "." {
                name.append("_")
            } else if !validCharacters.contains(c) {
                capnext = name.isEmpty ? capitalize : true
            } else if capnext {
                name.append(String(c).uppercased())
                capnext = false
            } else {
                name.append(c)
            }
        }
        return name
    }

    func dictionaryType(_ keyType: CodeType, _ valueType: CodeType) -> CodeExternalType {
        return CodeExternalType("Dictionary", generics: [keyType, valueType], defaultValue: "[:]")
    }

    func arrayType(_ type: CodeType) -> CodeExternalType {
        return CodeExternalType("Array", generics: [type], defaultValue: "[]", shorthand: (prefix: "[", suffix: "]"))
    }

    func collectionOfOneType(_ type: CodeType) -> CodeExternalType {
        return CodeExternalType("CollectionOfOne", generics: [type], defaultValue: "[]")
    }

    func optionalType(_ type: CodeType) -> CodeExternalType {
        return CodeExternalType("Optional", generics: [type], defaultValue: "nil", shorthand: (prefix: nil, suffix: "?"))
    }

    func indirectType(_ type: CodeType) -> CodeExternalType {
        return CodeExternalType("Indirect", generics: [type], defaultValue: "nil")
    }

    func nullableType(_ type: CodeType) -> CodeExternalType {
        return CodeExternalType("Nullable", generics: [type])
    }

    func oneOrManyType(_ type: CodeType) -> CodeExternalType {
        return CodeExternalType("OneOrMany", generics: [type])
    }

    func notBracType(_ type: CodeType) -> CodeExternalType {
        return CodeExternalType("NotBrac", generics: [type], defaultValue: "nil")
    }

    func nonEmptyType(_ type: CodeType) -> CodeExternalType {
        return CodeExternalType("NonEmptyCollection", generics: [type, arrayType(type)])
    }

    func oneOfType(_ codeTypes: [CodeType], promoteNullable: Bool = true, coalesceOneOrMany: Bool = true) -> CodeExternalType {
        var types = codeTypes
        if coalesceOneOrMany {
            // find any types that contain both `T` and `[T]` and turn them into a single `OneOrMany` type
            for (i, t) in types.enumerated() {
                // if let ai = types.firstIndex(where: { $0.identifier == arrayType(t).identifier }) {
                if i < types.count - 1 && types[i+1].identifier == arrayType(t).identifier  {
                    let ai = i+1 // for now we only coalesce adjacent types, since that is generally the convention and we don't want to unnecessarily coalesce types that don't have one-or-many semantice (e.g., RangeChoice = OneOf2<[Double], OneOrMany<String>>)
                    let oom = oneOrManyType(t)
                    types.remove(at: max(i, ai))
                    types[min(i, ai)] = oom // replace the type with the OneOrMany
                    break // we extract at most one
                }
            }
        }

        if types.count == 1 {
            return CodeExternalType(types[0].identifier)
        }

        var hasNullable = false

        // we normally leave the type order alone, but when a type is an `ExplicitNull`,
        // we need special handing because there is special decoder handling
        // when an `Optional` can contain an `ExplicitNull`; so we always promote
        // any `ExplicitNull` type to the front of the `OneOfX` type list.
        if let nullIndex = types.firstIndex(where: { $0.identifier == CodeExternalType.null.identifier }) {
            hasNullable = true
            let nullItem = types.remove(at: nullIndex)
            types.insert(nullItem, at: 0)
        }


        if hasNullable && promoteNullable {
            return nullableType(oneOfType(Array(types.dropFirst())))
        } else if types.count == 2 && hasNullable {
            return CodeExternalType("Nullable", generics: Array(types.dropFirst()))
        } else {
            return CodeExternalType("OneOf\(types.count)", generics: types)
        }
    }

    func anyOfType(_ types: [CodeType]) -> CodeExternalType {
        return CodeExternalType("AnyOf\(types.count)", generics: types)
    }

    func allOfType(_ types: [CodeType]) -> CodeExternalType {
        return CodeExternalType("AllOf\(types.count)", generics: types)
    }


    func typeName(_ parents: [CodeTypeName], _ id: String, capitalize: Bool = true) -> CodeTypeName {
        if let tname = renamer(parents, id) {
            return tname
        }

        var nm = id
        for pre in trimPrefixes {
            if nm.hasPrefix(pre) {
                nm = String(nm[pre.endIndex..<nm.endIndex])
            }
        }

        var name = sanitizeString(nm, capitalize: capitalize)

        if name.isSwiftKeyword() {
            name = "`" + name + "`"
        }

        if name.isEmpty { // e.g., ">=" -> "U62U61"
            for c in id.unicodeScalars {
                name += (enumCase == .upper ? "U" : "u") + "\(c.value)"
            }
        }
        return CodeTypeName(name)
    }

    func aliasType(_ type: CodeNamedType) -> CodeType? {
        if let alias = type as? CodeTypeAlias, alias.peerTypes.isEmpty {
            return alias.type
        } else {
            return nil
        }
    }

    /// Returns true if the schema will be serialized as a raw Bric instance
    func isBricType(_ schema: Schema) -> Bool {
        return false
//        var sch = schema
//        // trim out extranneous values
//        sch.description = nil
//
//        let bric = sch.bric()
//        if bric == [:] { return true }
//        if bric == ["type": "object"] { return true }
//
//        return false
    }

    typealias PropInfo = (name: String?, required: Bool, schema: Schema)
    typealias PropDec = (name: String, required: Bool, prop: Schema, anon: Bool)

    func getPropInfo(_ schema: Schema, id: String, parents: [CodeTypeName]) -> [PropInfo] {
        let properties = schema.properties ?? [:]

        /// JSON Schema Draft 4 doesn't have any notion of property ordering, so we use a user-defined sorter
        /// followed by ordering them by their appearance in the (non-standard) "propertyOrder" element
        /// followed by ordering them by their appearance in the "required" element
        /// followed by alphabetical property name ordering
        var ordering: [String] = []
        ordering.append(contentsOf: propOrdering(parents, id) ?? [])
        ordering.append(contentsOf: schema.propertyOrder ?? [])
        ordering.append(contentsOf: schema.required ?? [])
        ordering.append(contentsOf: properties.keys.sorted())
        
        let ordered = properties.sorted { a, b in return ordering.firstIndex(of: a.0)! <= ordering.firstIndex(of: b.0)! }
        let req = Set(schema.required ?? [])
        let props: [PropInfo] = ordered.map({ PropInfo(name: $0, required: req.contains($0), schema: $1) })
        return props
    }

    /// Encapsulates the given typename with the specified external type
    func encapsulateType(name typename: CodeTypeName, type: CodeExternalType, access: CodeAccess) -> CodeNamedType {
        let aliasType = type
        let propn = CodePropName("rawValue")
        let propd = CodeProperty.Declaration(name: propn, type: aliasType, access: access, mutable: true)
        var enc = CodeStruct(name: typename, access: access, props: [propd.implementation])

        enc.conforms += standardAdoptions
        enc.conforms.append(.rawCodable)

        for anon in [false, true] { // make both a named rawValue init as well as an anonymous one…
            let rawInit = CodeFunction.Declaration(name: "init", access: access, instance: true, exception: false, arguments: CodeTuple(elements: [(name: "rawValue", type: aliasType, value: nil, anon: anon)]), returns: CodeTuple(elements: []))
            let rawInitImp = CodeFunction.Implementation(declaration: rawInit, body: ["self.rawValue = rawValue"], comments: [])
            enc.funcs.append(rawInitImp)
        }

        // TODO: when wrapping String, should we also conform to ExpressibleByStringLiteral and create the initializer?

        return enc
    }

    /// Reifies the given schema as a Swift data structure
    public func reify(_ schema: Schema, id: String, parents parentsx: [CodeTypeName]) throws -> CodeNamedType {
        var parents = parentsx

        func selfType(_ type: CodeType, name: String?) -> CodeTupleElement {
            return CodeTupleElement(name: name, type: CodeExternalType(fullName(type), access: self.accessor(parents)), value: nil, anon: false)
        }

        let encodefun = CodeFunction.Declaration(name: "encode", access: accessor(parents), instance: true, exception: true, arguments: CodeTuple(elements: [(name: "to encoder", type: CodeExternalType.encoder, value: nil, anon: false)]), returns: CodeTuple(elements: []))
        let decodefun = CodeFunction.Declaration(name: "init", access: accessor(parents), instance: true, exception: true, arguments: CodeTuple(elements: [(name: "from decoder", type: CodeExternalType.decoder, value: nil, anon: false)]), returns: CodeTuple(elements: []))

        let comments = [schema.title, schema.description].compactMap { $0 }

        /// Calculate the fully-qualified name of the given type
        func fullName(_ type: CodeType) -> String {
            return (parents + [type.identifier]).joined(separator: ".")
        }

        func createUniqueName(_ props: [Curio.PropInfo], _ names: [CodeTypeName]) -> String {
            var name = ""
            for prop in props {
                name += sanitizeString(prop.name ?? "")
            }
            name += "Type"

            // ensure the name is unique
            var uniqueName = name
            var num = 0
            while names.contains(uniqueName) {
                num += 1
                uniqueName = name + String(num)
            }

            return uniqueName
        }

        func schemaTypeName(_ schema: Schema, types: [CodeType], suffix: String = "") -> String {
            if let titleName = schema.title.flatMap({ typeName(parents, $0) }) { return titleName }

            // before we fall-back to using a generic "Type" name, try to name a simple struct
            // from the names of all of its properties

            // a list of names to ensure that the type is unique
            let names = types.map({ ($0 as? CodeNamedType)?.name ?? "" }).filter({ !$0.isEmpty })

            let props = getPropInfo(schema, id: id, parents: parents)
            if props.count > 0 && props.count <= 5 {
                return createUniqueName(props, names)
            }

            return "Type" + suffix
        }

        func createOneOf(_ multi: [Schema]) throws -> CodeNamedType {
            let ename = typeName(parents, id)
            var code = CodeEnum(name: ename, access: accessor(parents))
            code.comments = comments

            var encodebody : [String] = []
            var decodebody : [String] = []

            encodebody.append("switch self {")
            decodebody.append("var errors: [Error] = []")

            var casenames = Set<String>()
            var casetypes = Array<CodeType>()
            for sub in multi {
                let casetype: CodeType

                switch sub.type {
                case .some(.v1(.string)) where sub._enum == nil: casetype = CodeExternalType.string
                case .some(.v1(.number)): casetype = CodeExternalType.number
                case .some(.v1(.boolean)): casetype = CodeExternalType.boolean
                case .some(.v1(.integer)): casetype = CodeExternalType.integer
                case .some(.v1(.null)): casetype = CodeExternalType.null
                default:
                    if let values = sub._enum {
                        let literalEnum = try createLiteralEnum(values: values)
                        code.nestedTypes.append(literalEnum) // we will later try to promote any CodeSimpleEnum<String> to be a peer of an alias type
                        casetype = literalEnum
                    } else {
                        // otherwise, create an anon sub-type (Type1, Type2, …)
                        let subtype = try reify(sub, id: schemaTypeName(sub, types: casetypes, suffix: String(code.nestedTypes.count+1)), parents: parents + [code.name])
                        // when the generated code is merely a typealias, just inline it in the enum case
                        if let aliasType = aliasType(subtype) {
                            casetype = aliasType
                        } else {
                            code.nestedTypes.append(subtype)

                            if generateValueTypes && subtype.directReferences.map(\.name).contains(ename) {
                                casetype = indirectType(subtype)
                            } else {
                                casetype = subtype
                            }
                        }
                    }
                }

                casetypes.append(casetype)
                let cname = typeName(parents, casetype.identifier, capitalize: enumCase == .upper) + caseSuffix

                var casename = cname
                if enumCase == .lower && casename.count > 2 {
                    // lower-case the case; just because it was not capitalized above does not mean it
                    // was lower-cases, because the case name may have been derived from a type name (list ArrayStringCase)
                    let initial = casename[casename.startIndex..<casename.index(after: casename.startIndex)]
                    let second = casename[casename.index(after: casename.startIndex)..<casename.index(after: casename.index(after: casename.startIndex))]
                    // only lower-case the type name if the second character is *not* upper-case; this heuristic
                    // is to prevent downcasing synonym types (e.g., we don't want "RGBCase" to be "rGBCase")
                    if second.uppercased() != second {
                        let remaining = casename[casename.index(after: casename.startIndex)..<casename.endIndex]
                        casename = initial.lowercased() + remaining
                    }
                }
                var n = 0
                // make sure case names are unique by suffixing with a number
                while casenames.contains(casename) {
                    n += 1
                    casename = cname + String(n)
                }
                casenames.insert(casename)
                code.cases.append(CodeEnum.Case(name: casename, type: casetype))

                if casetype.identifier == "Void" {
                    // Void can't be extended, so we need to special-case it to avoid calling methods on the type
                    encodebody.append("case .\(casename): try NSNull().encode(to: encoder)")
                    decodebody.append("do { try let _ = NSNull(from: decoder); self = .\(casename); return } catch { errors.append(error) }")
                } else {
                    encodebody.append("case .\(casename)(let x): try x.encode(to: encoder)")
                    decodebody.append("do { self = try .\(casename)(\(casetype.identifier)(from: decoder)); return } catch { errors.append(error) }")
                }

                // Also add a convenience init argument for the type that just accepts the associated value
                // The type should be unique, since they are OneOf types that aren't allowed to match
                let initfun = CodeFunction.Declaration(name: "init", access: accessor(parents), instance: true, arguments: CodeTuple(elements: [(name: "_ arg", type: casetype, value: nil, anon: false)]), returns: CodeTuple(elements: []))
                let initbody = [ "self = .\(casename)(arg)" ]
                let initimp = CodeFunction.Implementation(declaration: initfun, body: initbody, comments: ["Initializes with the \(casename) case"])
                code.funcs.append(initimp)
            }

            encodebody.append("}")
            decodebody.append("throw OneOfDecodingError(errors: errors)")

            code.conforms += standardAdoptions
            if generateCodable {
                code.funcs.append(CodeFunction.Implementation(declaration: encodefun, body: encodebody, comments: []))
                code.funcs.append(CodeFunction.Implementation(declaration: decodefun, body: decodebody, comments: []))
            }

            if useOneOfEnums && casetypes.count >= 2 && casetypes.count <= 10 {
                let constantEnums = code.nestedTypes.compactMap({ $0 as? CodeSimpleEnum<String> })
                if code.nestedTypes.count == constantEnums.count { // if there are no nested types, or they are all constant enums, we can simply return a typealias to the OneOfX type
                    return aliasOneOf(casetypes, name: ename, optional: false, defined: parents.isEmpty, peerTypes: constantEnums)
                } else { // otherwise we need to continue to use the nested inner types in a hollow enum and return the typealias
                    let choiceName = oneOfSuffix
                    let aliasName = ename + (parents.isEmpty ? "" : choiceName) // top-level aliases are fully-qualified types because they are defined in defs and refs
                    // the enum code now just contains the nested types, so copy over only the embedded types
                    let nestedAlias = CodeTypeAlias(name: choiceName, type: oneOfType(casetypes), access: accessor(parents))
                    var nestedEnum = CodeEnum(name: ename + "Types", access: accessor(parents))
                    nestedEnum.nestedTypes = [nestedAlias] + code.nestedTypes

                    // FIXME: alias to nested type doesn't seem to work
                    // let aliasRef = CodeExternalType(typeName([nestedEnum.name], choiceName), access: accessor(parents))
                    let aliasRef = CodeExternalType(nestedEnum.name + "." + choiceName, access: accessor(parents))

                    var alias = CodeTypeAlias(name: aliasName, type: aliasRef, access: accessor(parents))
                    alias.comments = comments
                    alias.peerTypes = [nestedEnum]

                    return alias
                }
            }

            return code
        }

        func createSimpleEnumeration(_ typename: CodeTypeName, name: String, types: [Schema.SimpleTypes]) -> CodeNamedType {
            var assoc = CodeEnum(name: typeName(parents, name), access: accessor(parents + [typeName(parents, name)]))

            var subTypes: [CodeType] = []
            let optional = false

            for (_, sub) in types.enumerated() {
                switch sub {
                case .string:
                    let caseName = enumCase == .upper ? "Text" : "text"
                    subTypes.append(CodeExternalType.string)
                    assoc.cases.append(CodeEnum.Case(name: caseName, type: CodeExternalType.string))
                case .number:
                    let caseName = enumCase == .upper ? "Number" : "number"
                    subTypes.append(CodeExternalType.number)
                    assoc.cases.append(CodeEnum.Case(name: caseName, type: CodeExternalType.number))
                case .boolean:
                    let caseName = enumCase == .upper ? "Boolean" : "boolean"
                    subTypes.append(CodeExternalType.boolean)
                    assoc.cases.append(CodeEnum.Case(name: caseName, type: CodeExternalType.boolean))
                case .integer:
                    let caseName = enumCase == .upper ? "Integer" : "integer"
                    subTypes.append(CodeExternalType.integer)
                    assoc.cases.append(CodeEnum.Case(name: caseName, type: CodeExternalType.integer))
                case .array:
                    let caseName = enumCase == .upper ? "List" : "list"
                    subTypes.append(CodeExternalType.array)
                    assoc.cases.append(CodeEnum.Case(name: caseName, type: CodeExternalType.array))
                case .object:
                    let caseName = enumCase == .upper ? "Object" : "object"
                    //print("warning: making Bric for key: \(name)")
                    subTypes.append(CodeExternalType.bric)
                    assoc.cases.append(CodeEnum.Case(name: caseName, type: CodeExternalType.bric))
                case .null:
                    let caseName = enumCase == .upper ? "None" : "none"
                    subTypes.append(CodeExternalType.null)
//                    optional = true
                    assoc.cases.append(CodeEnum.Case(name: caseName, type: nil))
                }
            }

            assoc.conforms += standardAdoptions
            parents += [typename]
            parents = Array(parents.dropLast())

            if subTypes.count > 0 {
                return aliasOneOf(subTypes, name: assoc.name, optional: optional, defined: parents.isEmpty)
            }

            return assoc
        }

        func aliasOneOf(_ subTypes: [CodeType], name typename: CodeTypeName, optional: Bool, defined: Bool, peerTypes: [CodeNamedType] = []) -> CodeNamedType {
            // There's no OneOf1; this can happen e.g. when a schema has types: ["double", "null"]
            // In these cases, simply return an alias to the types
            let aname = defined ? typename : (unescape(typename) + oneOfSuffix)

            // typealiases to OneOfX work but are difficult to extend (e.g., generic types cannot conform to the same protocol with different type constraints), so we add an additional level of serialization-compatible indirection
            if let encapsulatedType = self.encapsulate[typename], peerTypes.isEmpty, !optional, subTypes.count > 1, defined {
                let wrapType = encapsulatedType.name == typename ? oneOfType(subTypes) : encapsulatedType
                return encapsulateType(name: typename, type: wrapType, access: accessor(parents))
            }

            let type = subTypes.count == 1 ? subTypes[0] : oneOfType(subTypes)
            var alias = CodeTypeAlias(name: aname, type: optional ? optionalType(type) : type, access: accessor(parents), peerTypes: peerTypes)
            alias.comments = comments
            return alias
        }

        func aliasSimpleType(name typename: CodeTypeName, type: CodeExternalType) -> CodeNamedType {
            // When we encapsulate a typealias (e.g., Color = String), we make it into a separate type that can be extended
            if let encapsulatedType = self.encapsulate[typename] {
                // if the encapsulated type name is exactly the same as the typename, then that means we should encapsulate
                // with the preserved type name. E.g., if "FontWeight = OneOf2<String, Double>" and we encapsulate "FontWeight" = "FontWeight", then we will just generate a raw represented struct FontWeight { rawValue: OneOf2<String, Double> }
                let wrapType = encapsulatedType.name == typename ? type : encapsulatedType
                return encapsulateType(name: typename, type: wrapType, access: accessor(parents))
            }
            return CodeTypeAlias(name: typename, type: type, access: accessor(parents))
        }

        enum StateMode { case standard, allOf, anyOf }

        /// Creates a schema instance for an "object" type with all the listed properties
        func createObject(_ typename: CodeTypeName, properties: [PropInfo], mode: StateMode) throws -> CodeNamedType {
            let isUnionType = mode == .allOf || mode == .anyOf

            var code: CodeStateType
            if generateValueTypes {
                code = CodeStruct(name: typename, access: accessor(parents + [typename]))
            } else {
                code = CodeClass(name: typename, access: accessor(parents + [typename]))
            }

            code.comments = comments

            typealias PropNameType = (name: CodePropName, type: CodeType)
            var proptypes: [PropNameType] = []

            // assign some anonymous names to the properties
            var anonPropCount = 0
            func incrementAnonPropCount() -> Int {
                anonPropCount += 1
                return anonPropCount - 1
            }
            let props: [PropDec] = properties
                .map({
                    PropDec(name: $0.name ?? propName(parents, "p\(incrementAnonPropCount())"), required: $0.required, prop: $0.schema, anon: $0.name == nil)
                })
                .filter({ name, required, prop, anon in
                    !excludes.contains(typename + "." + name)
                })

            for (name, var required, prop, anon) in props {
                let _ = anon
                var proptype: CodeType

                let propPath = typename + "." + name

                let forceIndirect = propertyIndirects.contains(propPath)

                if let overrideType = propertyTypeOverrides[propPath] {
                    proptype = CodeExternalType(overrideType, access: accessor(parents + [typename]))
                    if !required && overrideType.hasSuffix("!") {
                        required = true // the type can also override the required-ness with a "!"
                    }
                } else if let ref = prop.ref {
                    let tname = typeName(parents, ref)
                    proptype = CodeExternalType(tname, access: accessor(parents + [typename]))
                } else {
                    switch prop.type {
                    case .some(.v1(.string)) where prop._enum == nil: proptype = CodeExternalType.string
                    case .some(.v1(.number)): proptype = CodeExternalType.number
                    case .some(.v1(.boolean)): proptype = CodeExternalType.boolean
                    case .some(.v1(.integer)): proptype = CodeExternalType.integer
                    case .some(.v1(.null)): proptype = CodeExternalType.null

                    case .some(.v2(let types)):
                        let assoc = createSimpleEnumeration(typename, name: name, types: types)
                        code.nestedTypes.append(assoc)
                        proptype = assoc

                    case .some(.v1(.array)):
                        // a set of all the items, eliminating duplicates; this eliminated redundant schema declarations in the items list
                        let items: Set<Schema> = Set(prop.items?.v2 ?? prop.items?.v1.flatMap({ [$0] }) ?? [])

                        switch items.count {
                        case 0:
                            proptype = arrayType(CodeExternalType.bric)
                        case 1:
                            let item = items.first!
                            if let ref = item.ref {
                                proptype = arrayType(CodeExternalType(typeName(parents, ref), access: accessor(parents)))
                            } else {
                                let type = try reify(item, id: name + "Item", parents: parents + [code.name])
                                code.nestedTypes.append(type)
                                proptype = arrayType(type)
                            }
                        default:
                            throw CodegenErrors.typeArrayNotSupported
                        }

                    default:
                        // generate the type for the object
                        let subtype = try reify(prop, id: prop.title ?? (sanitizeString(name) + typeSuffix), parents: parents + [code.name])
                        code.nestedTypes.append(subtype)
                        proptype = subtype
                    }
                }

                var indirect: CodeType?

                if !required {
                    let structProps = props.filter({ (name, required, prop, anon) in

                        var types: [Schema.SimpleTypes] = prop.type?.tupleValue.1 ?? []
                        if let typ = prop.type?.tupleValue.0 { types.append(typ) }

                        switch types.first {
                        case .none: return true // unspecified object type: maybe a $ref
                        case .some(.object): return true // a custom object
                        default: return false // raw types never get an indirect
                        }
                    })

                    if forceIndirect || structProps.count >= self.indirectCountThreshold {
                        indirect = optionalType(indirectType(proptype))
                    }
                    proptype = optionalType(proptype)
                }

                let propn = propName(parents + [typename], name)
                var propd = CodeProperty.Declaration(name: propn, type: proptype, access: accessor(parents))
                propd.comments = [prop.title, prop.description].compactMap { $0 }

                var propi = propd.implementation

                // indirect properties are stored privately as _prop vars with cover wrappers that convert them to optionals
                if let indirect = indirect {
                    let ipropn = propName(parents + [typename], indirectPrefix + name)
                    let ipropd = CodeProperty.Declaration(name: ipropn, type: indirect, access: .`private`)
                    let ipropi = ipropd.implementation
                    code.props.append(ipropi)

                    propi.body = [
                        "get { return " + ipropn + "?.wrappedValue }",
                        "set { " + ipropn + " = newValue.indirect() }",
                    ]
                }


                code.props.append(propi)
                let pt: PropNameType = (name: propn, type: proptype)
                proptypes.append(pt)
            }

            let addPropType: CodeType? = nil
            let hasAdditionalProps: Bool? // true=yes, false=no, nil=unspecified

            // currently we simply choose to allow or forbid additionalProperties
            // we should also implement support for an additionalProperties schema values
            // e.g., `"additionalProperties": { "type": "number" }` should generate:
            // typealias AdditionalPropertiesValue = Double
            // var additionalProperties: [String: AdditionalPropertiesValue]?
            switch schema.additionalProperties {
            case .none:
                hasAdditionalProps = nil // TODO: make a global default for whether unspecified additionalProperties means yes or no
            case .some(.v1(false)):
                hasAdditionalProps = nil // FIXME: when this is false, allOf union types won't validate
            case .some(.v1(true)), .some(.v2):
                hasAdditionalProps = nil // TODO: generate object types for B
                //hasAdditionalProps = true
                //addPropType = CodeExternalType.object // additionalProperties default to [String:Bric]
            }

            let addPropName = renamer(parents, "additionalProperties") ?? "additionalProperties"

            func keyName(_ prop: CodeProperty.Declaration) -> String {
                keyName(name: prop.name)
            }

            func keyName(name: String) -> String {
                let propPath = typename + "." + name
                let forceIndirect = propertyIndirects.contains(propPath)
                return (forceIndirect ? "_" : "") + name
            }

            if let addPropType = addPropType {
                let propn = propName(parents + [typename], addPropName)
                let propd = CodeProperty.Declaration(name: propn, type: addPropType, access: accessor(parents))
                let propi = propd.implementation
                code.props.append(propi)
                if hasAdditionalProps != false { } // TODO
                let _: PropNameType = (name: propn, type: addPropType)
//                proptypes.append(pt)
            }

            /// Creates a Keys enumeration of all the valid keys for this state instance
            func makeKeys(_ keysName: String) {
                var cases: [CodeCaseSimple<String>] = []
                for (name, _, _, _) in props {
                    let propPath = typename + "." + name
                    let forceIndirect = propertyIndirects.contains(propPath)

                    let pname = propName(parents + [typename], (forceIndirect ? indirectPrefix : "") + name)
                    cases.append(CodeCaseSimple(name: pname, value: name))
                }

                if addPropType != nil {
                    cases.append(CodeCaseSimple(name: addPropName, value: ""))
                }

                if !cases.isEmpty {
                    var keysType = CodeSimpleEnum(name: keysName, access: accessor(parents), cases: cases)
                    keysType.conforms.append(.codingKey)
                    keysType.conforms.append(.hashable)
                    keysType.conforms.append(.codable)
                    keysType.conforms.append(.caseIterable)

                    if generateIdentifiable == true { // "var id: Self { self }"
                        keysType.conforms.append(.identifiable)
                        keysType.props.append(CodeProperty.Implementation(declaration: CodeProperty.Declaration(name: "id", type: CodeExternalType("Self"), access: accessor(parents), instance: true, mutable: false), value: nil, body: ["self"], comments: []))
                    }

                    // Add in a "CodingOwner" typealias to the owner
                    if let codingOwner = codingOwner {
                        let ownerAlias = CodeTypeAlias(name: codingOwner, type: code, access: accessor(parents))
                        keysType.nestedTypes.insert(ownerAlias, at: 0)
                    }

                    if keyDescriptionMethod == true {
                        var keysBody: [String] = []
                        keysBody.append("switch self {")

                        for (key, _, prop, _) in props {
                            let pname = propName(parents + [typename], key)
                            cases.append(CodeCaseSimple(name: pname, value: key))
                            let desc = prop.description?.enquote("\"").replace(character: "\n", with: "\\n") ?? "nil"
                            let kname = keyName(name: pname)
                            keysBody.append("case .\(kname): return \(desc)")
                        }

                        keysBody.append(" } ")

                        keysType.props.append(CodeProperty.Implementation(declaration: CodeProperty.Declaration(name: "keyDescription", type: optionalType(CodeExternalType.string), access: accessor(parents), instance: true, mutable: false), value: nil, body: keysBody, comments: []))
                    }

                    code.nestedTypes.insert(keysType, at: 0)
                }
            }

            // "static let codingKeyPaths = (\Self.x, \Self.y, …)"
            func makeCodingKeyPaths() {
                let vars = code.props.filter { $0.declaration.instance == true && $0.body.isEmpty } // i.e., not static vars
                if vars.isEmpty { return }

                let codingKeyPathsValue = "("
                    + vars.map({ "\\Self.\($0.declaration.name)" }).joined(separator: ", ")
                    + ")"

                code.props.append(CodeProperty.Implementation(declaration: CodeProperty.Declaration(name: "codingKeyPaths", type: nil, access: accessor(parents), instance: false, mutable: false), value: codingKeyPathsValue, body: [], comments: []))
            }

            //     static let codableKeys: [PartialKeyPath<Self> : Self.CodingKeys] = [\Self.x: CodingKeys.x, \Self.y: CodingKeys.y]
            func makeCodableKeys() {
                let vars = code.props.filter { $0.declaration.instance == true && $0.body.isEmpty } // i.e., not static vars
                if vars.isEmpty { return }

                let codableKeysValue = "["
                    + vars.map({ "\\Self.\($0.declaration.name) : CodingKeys.\($0.declaration.name)" }).joined(separator: ", ")
                    + "]"

                let codableKeysType = dictionaryType(CodeExternalType("PartialKeyPath", generics: [CodeExternalType("Self")]), CodeExternalType("CodingKeys"))

                code.props.append(CodeProperty.Implementation(declaration: CodeProperty.Declaration(name: "codableKeys", type: codableKeysType, access: accessor(parents), instance: false, mutable: false), value: codableKeysValue, body: [], comments: []))
            }

            /// Creates a memberwise initializer for the object type
            func makeInit(_ merged: Bool) {
                var elements: [CodeTupleElement] = []
                var initbody: [String] = []
                var wasIndirect = false
                for p1 in code.props {
                    if p1.declaration.name.hasPrefix(indirectPrefix) {
                        wasIndirect = true
                    } else {
                        // allOf merged will take any sub-states and create initializers with all of their arguments
                        let sub = merged ? p1.declaration.type as? CodeStateType : nil
                        for p in (sub?.props ?? [p1]) {
                            let d = p.declaration
                            let e = CodeTupleElement(name: d.name, type: d.type, value: d.type?.defaultValue, anon: isUnionType)

                            elements.append(e)
                            if wasIndirect {
                                // unescape is a hack because we don't preserve the original property name, so we need to
                                // do self._case = XXX instead of self._`case` = XXX
                                initbody.append("self.\(indirectPrefix)\(unescape(d.name)) = \(d.name).indirect()")
                                wasIndirect = false
                            } else {
                                initbody.append("self.\(d.name) = \(d.name)")
                            }
                        }
                    }
                }


                // for the init declaration, unescape all the elements and only re-escape them if they are the few forbidden keywords
                // https://github.com/apple/swift-evolution/blob/master/proposals/0001-keywords-as-argument-labels.md
                var argElements = elements
                for i in 0..<argElements.count {
                    if var name = argElements[i].name {
                        let unescaped = unescape(name)
                        if unescaped.isSwiftReservedArg() {
                            name = "`" + unescaped + "`"
                        }
                        argElements[i].name = name
                    }
                }

                let initargs = CodeTuple(elements: argElements)
                let initfun = CodeFunction.Declaration(name: "init", access: accessor(parents), instance: true, arguments: initargs, returns: CodeTuple(elements: []))
                let initimp = CodeFunction.Implementation(declaration: initfun, body: initbody, comments: [])
                code.funcs.append(initimp)
            }

            /// Creates a custom decoder for special `Optional<Nullable<T>>` handling (which the synthesized decoders don't handle correctly)
            func makeDecodable(permitSynthesizedImplementation: Bool = false) {
                var decodebody: [String] = [ ]

                if schema.additionalProperties == nil || schema.additionalProperties?.infer() == false {
                    // forbid additional properties before we try to decode the other value – this should help decoding performance by failing quietly on invalid schemas before we dig into the decodability of nested properties
                    decodebody.append("try decoder.forbidAdditionalProperties(notContainedIn: CodingKeys.allCases)")
                }

                    //"func keytype<Value>(_ kp: KeyPath<Self, Value>) -> Value.Type { Value.self }",
                decodebody.append("let values = try decoder.container(keyedBy: CodingKeys.self)")

                for p in code.props {
                    let d = p.declaration
                    if let typ = p.declaration.type {
                        var id = typ.identifier
                        if id.hasSuffix("!") { id = String(id.dropLast(1)) }
                        let kname = keyName(d)
                        if id.hasSuffix("?") {
                            id = String(id.dropLast(1)) // decode non-optional version

                            decodebody.append("self.\(d.name) = try values.decodeOptional(\(id).self, forKey: .\(kname))")
                        } else {
                            decodebody.append("self.\(d.name) = try values.decode(\(id).self, forKey: .\(kname))")
                        }
                    }
                }

                let decodefun = CodeFunction.Declaration(name: "init", access: accessor(parents), instance: true, exception: true, arguments: CodeTuple(elements: [(name: "from decoder", type: CodeExternalType.decoder, value: nil, anon: false)]), returns: CodeTuple(elements: []))
                let decodeimp = CodeFunction.Implementation(declaration: decodefun, body: decodebody, comments: [])
                code.funcs.append(decodeimp)
            }


            let keysName = "CodingKeys"
            if !isUnionType {
                // create an enumeration of "Keys" for all the object's properties
                makeKeys(keysName)
            }

            makeInit(false)
            makeDecodable()
            code.conforms += standardAdoptions

            if generateKeyedCodable {
                makeCodingKeyPaths()
                makeCodableKeys()
                code.conforms += [.keyedCodable]
            }

            let reftypes = proptypes.map(\.type)
            if (mode == .allOf || mode == .anyOf) && useAllOfEnums && reftypes.count >= 2 && reftypes.count <= 10 {
                let suffix = mode == .allOf ? allOfSuffix : anyOfSuffix
                let sumType = mode == .allOf ? allOfType(reftypes) : anyOfType(reftypes)

                if code.nestedTypes.isEmpty { // if there are no nested types, we can simply return a typealias to the AllOfX type
                    var alias = CodeTypeAlias(name: code.name, type: sumType, access: accessor(parents))
                    alias.comments = comments
                    return alias
                } else { // otherwise we need to continue to use the nested inner types in a hollow enum and return the typealias
                    let choiceName = suffix
                    // the enum code now just contains the nested types, so copy over only the embedded types
                    let nestedAlias = CodeTypeAlias(name: choiceName, type: sumType, access: accessor(parents))
                    var nestedEnum = CodeEnum(name: code.name + "Types", access: accessor(parents))
                    nestedEnum.nestedTypes = [nestedAlias] + code.nestedTypes

                    // FIXME: alias to nested type doesn't seem to work
                    // let aliasRef = CodeExternalType(typeName([nestedEnum.name], choiceName), access: accessor(parents))
                    let aliasRef = CodeExternalType(nestedEnum.name + "." + choiceName, access: accessor(parents))

                    var alias = CodeTypeAlias(name: code.name, type: aliasRef, access: accessor(parents))
                    alias.comments = comments
                    alias.peerTypes = [nestedEnum]

                    return alias
                }
            }

            return code
        }

        func createArray(_ typename: CodeTypeName) throws -> CodeNamedType {
            // when a top-level type is an array, we make it a typealias with a type for the individual elements
            let items: Set<Schema>
            switch schema.items {
            case .none: items = []
            case .some(.v1(let value)): items = [value]
            case .some(.v2(let values)): items = .init(values)
            }

            if items.isEmpty {
                return CodeTypeAlias(name: typeName(parents, id), type: arrayType(CodeExternalType.bric), access: accessor(parents))
            } else if let item = items.first, items.count == 1 {
                    if let ref = item.ref {
                        return CodeTypeAlias(name: typeName(parents, id), type: arrayType(CodeExternalType(typeName(parents, ref), access: accessor(parents))), access: accessor(parents))
                    } else {
                        // note that we do not tack on the alias' name, because it will not be used as the external name of the type
                        let type = try reify(item, id: typename + "Item", parents: parents)

                        // rather than creating two aliases when something is an array of an alias, merge them as a single unit
                        if let sub = aliasType(type) {
                            return CodeTypeAlias(name: typeName(parents, id), type: arrayType(sub), access: accessor(parents))
                        } else {
                            let alias = CodeTypeAlias(name: typeName(parents, id), type: arrayType(type), access: accessor(parents), peerTypes: [type])
                            return alias
                        }
                    }
            } else {
                throw CodegenErrors.typeArrayNotSupported
            }
        }

        func createLiteralEnum(_ name: CodeTypeName? = nil, values: [Bric]) throws -> CodeNamedType {
            // some languages (like Typescript) commonly have union types that are like: var intOrConstant: number | "someConst"
            // when a string enum has fewer values than constantPromotionThreshold, we promote the type to the top level to global use
            let valueTypeNames = typeName(parents, "Literal" + values.map({ $0.stringify() }).joined(separator: "Or"), capitalize: true)

            var stringEnum = CodeSimpleEnum<String>(name: name ?? valueTypeNames, access: accessor(parents))
            var numberEnum = CodeSimpleEnum<Double>(name: name ?? valueTypeNames, access: accessor(parents))
            var boolEnum = CodeSimpleEnum<Bool>(name: name ?? valueTypeNames, access: accessor(parents))
            for e in values {
                if case .str(let evalue) = e {
                    stringEnum.cases.append(.init(name: typeName(parents, evalue, capitalize: enumCase == .upper), value: evalue))
                } else if case .num(let evalue) = e {
                    numberEnum.cases.append(.init(name: typeName(parents, evalue.description, capitalize: enumCase == .upper), value: evalue))
                } else if case .bol(let evalue) = e {
                    boolEnum.cases.append(.init(name: typeName(parents, evalue.description, capitalize: enumCase == .upper), value: evalue))
                } else {
                    throw CodegenErrors.nonStringEnumsNotSupported
                }
            }

            func finishEnum<T>(_ code: CodeSimpleEnum<T>) -> CodeEnumType {
                var code = code
                // when there is only a single possible value, make it the default
                if let firstCase = code.cases.first, code.cases.count == 1 {
                    code.defaultValue = "." + firstCase.name
                }

                code.conforms += standardAdoptions
                code.conforms.append(.caseIterable)
                code.comments = comments
                return code
            }

            let stringEnumCode = stringEnum.cases.isEmpty ? nil : finishEnum(stringEnum)
            let numberEnumCode = numberEnum.cases.isEmpty ? nil : finishEnum(numberEnum)
            let boolEnumCode = boolEnum.cases.isEmpty ? nil : finishEnum(boolEnum)

            let enumTypes: [CodeEnumType] = [stringEnumCode, numberEnumCode, boolEnumCode].compactMap({ $0 })
            switch enumTypes.count {
            case 0:
                throw CodegenErrors.emptyEnum
            case 1: // just return the type directly
                return enumTypes[0]
            case _: // multiple enums form a OneOfX for each type
                var enumTypes = enumTypes
                enumTypes = enumTypes.map { enumType in
                    var enumType = enumType
                    enumType.name = enumType.name + enumType.associatedTypeName // suffix the type with the type
                    return enumType
                }
                return aliasOneOf(enumTypes, name: name ?? valueTypeNames, optional: false, defined: true, peerTypes: enumTypes)
            }
        }

        let type = schema.type
        let typename = typeName(parents, id)
        let explicitName = id.hasPrefix("#") // explicit named like "#/definitions/LocalMultiTimeUnit" must be used literally
        if var values = schema._enum {
            // when creating a string enum, explcit names must be used, otherwise we generate a name like "LiteralXOrYOrZ"
            var containsNul = false
            if let nulIndex = values.firstIndex(of: .nul) {
                values.remove(at: nulIndex)
                containsNul = true
            }
            let senum = try createLiteralEnum(explicitName ? typename : nil, values: values)
            // TODO: make OneOf(ExplicitNull, ...)
            return containsNul ? senum : senum
        } else if case .some(.v2(let multiType)) = type {
            // "type": ["string", "number"]
            var subTypes: [CodeType] = []
            for type in multiType {
                switch type {
                case .array: subTypes.append(arrayType(CodeExternalType.bric))
                case .boolean: subTypes.append(CodeExternalType.boolean)
                case .integer: subTypes.append(CodeExternalType.integer)
                case .null: subTypes.append(CodeExternalType.null)
                case .number: subTypes.append(CodeExternalType.number)
                case .object: subTypes.append(CodeExternalType.bric)
                case .string: subTypes.append(CodeExternalType.string)
                }
            }
            return aliasOneOf(subTypes, name: typename, optional: false, defined: parents.isEmpty)
        } else if case .some(.v1(.string)) = type {
            return aliasSimpleType(name: typename, type: CodeExternalType.string)
        } else if case .some(.v1(.integer)) = type {
            return aliasSimpleType(name: typename, type: CodeExternalType.integer)
        } else if case .some(.v1(.number)) = type {
            return aliasSimpleType(name: typename, type: CodeExternalType.number)
        } else if case .some(.v1(.boolean)) = type {
            return aliasSimpleType(name: typename, type: CodeExternalType.boolean)
        } else if case .some(.v1(.null)) = type {
            return aliasSimpleType(name: typename, type: CodeExternalType.null)
        } else if case .some(.v1(.array)) = type {
            return try createArray(typename)
        } else if let properties = schema.properties, !properties.isEmpty {
            return try createObject(typename, properties: getPropInfo(schema, id: id, parents: parents), mode: .standard)
        } else if let allOf = schema.allOf {
            // represent allOf as a struct with non-optional properties
            var props: [PropInfo] = []
            for propSchema in allOf {
                // an internal nested state type can be safely collapsed into the owning object
                // not working for a few reasons, one of which is bric merge info
//                if let subProps = propSchema.properties where !subProps.isEmpty {
//                    props.appendContentsOf(getPropInfo(subProps))
//                    // TODO: sub-schema "required" array
//                } else {
                    props.append(PropInfo(name: nil, required: true, schema: propSchema))
//                }
            }
            return try createObject(typename, properties: props, mode: .allOf)
        } else if let anyOf = schema.anyOf {
            if anyOfAsOneOf {
                // some schemas mis-interpret anyOf to mean oneOf, so redirect them to oneOfs
                return try createOneOf(anyOf)
            }
            var props: [PropInfo] = []
            for propSchema in anyOf {
                // if !isBricType(propSchema) { continue } // anyOfs disallow misc Bric types // disabled because this is sometimes used in an allOf to validate peer properties
                props.append(PropInfo(name: nil, required: false, schema: propSchema))
            }
            if props.count == 1 { props[0].required = true }

            // AnyOfs with only 1 property are AllOf
            return try createObject(typename, properties: props, mode: props.count > 1 ? .anyOf : .allOf)
        } else if let oneOf = schema.oneOf { // TODO: allows properties in addition to oneOf
            return try createOneOf(oneOf)
        } else if let ref = schema.ref { // create a typealias to the reference
            let tname = typeName(parents, ref)
            let extern = CodeExternalType(tname)
            return CodeTypeAlias(name: typename == tname ? typename + "Type" : typename, type: extern, access: accessor(parents))
        } else if let not = schema.not?.wrappedValue, (try not.bricEncoded()).count > 0 { // a "not" generates a validator against an inverse schema, but only if it isn't empty
            let inverseId = "Not" + typename
            let inverseSchema = try reify(not, id: inverseId, parents: parents)
            return CodeTypeAlias(name: typename, type: notBracType(inverseSchema), access: accessor(parents), peerTypes: [inverseSchema])
            // TODO
//        } else if let req = schema.required where !req.isEmpty { // a sub-bric with only required properties just validates
//            let reqId = "Req" + typename
//            let reqSchema = try reify(not, id: reqId, parents: parents)
//            return CodeTypeAlias(name: typename, type: notBracType(reqSchema), access: accessor(parents), peerTypes: [reqSchema])
        } else if isBricType(schema) { // an empty schema just generates pure Bric
            return CodeTypeAlias(name: typename, type: CodeExternalType.bric, access: accessor(parents))
        } else if case .some(.v1(.object)) = type, case let .some(.v2(adp)) = schema.additionalProperties {
            // an empty schema with additionalProperties makes it a [String:Type]
            let adpType = try reify(adp, id: typename + "Value", parents: parents)
            return CodeTypeAlias(name: typename, type: dictionaryType(CodeExternalType.string, adpType), access: accessor(parents), peerTypes: [adpType])
        } else if case .some(.v1(.object)) = type, case .some(.v1(true)) = schema.additionalProperties {
            // an empty schema with additionalProperties makes it a [String:Bric]
            //print("warning: making Brictionary for code: \(schema.bric().stringify())")
            return CodeTypeAlias(name: typename, type: CodeExternalType.object, access: self.accessor(parents))
        } else {
            // throw CodegenErrors.illegalState("No code to generate for: \(schema.bric().stringify())")
//            print("warning: making HollowBric for code: \(schema.bric().stringify())")
            return CodeTypeAlias(name: typename, type: CodeExternalType.bric, access: self.accessor(parents))
        }
    }


    /// Parses the given schema source into a module; if the rootSchema is non-nil, then all the schemas
    /// will be generated beneath the given root
    public func assemble(_ schemas: [(String, Schema)], rootName: String? = nil) throws -> CodeModule {

        var types: [CodeNamedType] = []
        for (key, schema) in schemas {
            if key == rootName { continue }
            types.append(try reify(schema, id: key, parents: []))
        }

        let rootSchema = schemas.filter({ $0.0 == rootName }).first?.1
        let module = CodeModule()

        // next, promote all of the types for promoteIdenticalTypes
        if promoteIdenticalTypes {
            func flattenedTypes(_ types: [CodeNamedType]) -> [CodeNamedType] {
                let nestedTypes = types.compactMap({ $0 as? CodeStateType }).flatMap({ $0.nestedTypes  })
                let peerTypes = types.compactMap({ $0 as? CodeTypeAlias }).flatMap({ $0.peerTypes  })
                if nestedTypes.isEmpty && peerTypes.isEmpty { return types }
                return types + flattenedTypes(nestedTypes) + flattenedTypes(peerTypes)
            }

            let deepTypes = flattenedTypes(types)

            func duplicatedTypes<T : CodeNamedType & Hashable>(_ typeList: [T], from: [CodeNamedType]) -> Set<T> {
                var typeCounts: [T: Int] = [:]
                for checkType in typeList {
                    typeCounts[checkType] = (typeCounts[checkType] ?? 0) + 1
                }

                var dupes: Set<T> = []
                for (type, count) in typeCounts {
                    // any types that have more than one count and are not a "CodingKeys" type can be promoted to the top-level
                    if count > 1 && type.identifier != "CodingKeys" {
                        dupes.insert(type)
                    }
                }

                return dupes
            }

            func promoteTypes<T: CodeNamedType & Hashable>(_ array: [T]) {
                var promotedTypes = duplicatedTypes(array, from: types)

                types = types.map({ $0.purgeTypes(promotedTypes) })

                // de-dupe promoted types: this can happen when there are two type names that have different description comments (e.g., LiteralWidth)
                for (typeName, typeValues) in Dictionary(grouping: promotedTypes, by: { $0.name }) {
                    if typeValues.count > 1 {
                        print("// warning: excluding \(typeValues.count) duplicate type names for \(typeName)")
                        for drop in typeValues.sorted(by: { $0.codeValue < $1.codeValue }).dropFirst() {
                            promotedTypes.remove(drop) // clear out duplicates
                        }
                    }
                }

                types += Array(promotedTypes) // tack on the de-duplicated promoted types
            }

            // we currently just promote string enums & typealiases, since those are the most common shared code we've observed
            promoteTypes(deepTypes.compactMap({ $0 as? CodeSimpleEnum<String> }))

            // also promote type aliases – not currently working (there are top-level duplicates)
            // promoteTypes(deepTypes.compactMap({ $0 as? CodeTypeAlias }))

            // next add in any encapsulated types we have specified that might not actually
            // have been defined in the schema; this allows us to encapsulate things
            // into wrappers without them being treated specially by the schema
            for (name, type) in self.encapsulate {
                if !deepTypes.contains(where: { $0.name == name }) {
                    let encap = encapsulateType(name: name, type: type, access: accessor([]))
                    types.append(encap)
                }
            }

            // this doesn't quite work because we have some conflicting types for common cases (e.g., "Value")
            // types = promoteTypes(deepTypes.compactMap({ $0 as? CodeTypeAlias }), from: types)
        }

        // lastly we filter out all the excluded types we want to skip
        types = types.filter({ !excludes.contains($0.name) })

        if let rootSchema = rootSchema {
            let code = try reify(rootSchema, id: rootName ?? "Schema", parents: [])
            if var root = code as? CodeStateType {
                root.nestedTypes.append(contentsOf: types)
                module.types = [root]
            } else {
                module.types = [code]
                module.types.append(contentsOf: types)
            }
        } else {
            module.types = types
        }

        // add in a root enumeration for all the types
        if let registryTypeName = registryTypeName {
            var registryType = CodeEnum(name: registryTypeName, access: accessor([]))
            let allTypes = module.types.sorted(by: { $0.name < $1.name })

            func addRegistryTypes<T: CodeNamedType>(name: String, types: [T]) {
                if types.isEmpty { return } // cannot create an empty enum
                var registryEnum = CodeSimpleEnum<String>(name: name, access: accessor([]))
                registryEnum.conforms += [.caseIterable, .hashable]
                for type in types {
                    registryEnum.cases.append(.init(name: type.name, value: type.name))
                }
                registryType.nestedTypes += [registryEnum]
            }

            addRegistryTypes(name: "Structs", types: allTypes.compactMap({ $0 as? CodeStruct }).filter({ !$0.conforms.contains(.rawCodable) }))
            addRegistryTypes(name: "Wrappers", types: allTypes.compactMap({ $0 as? CodeStruct }).filter({ $0.conforms.contains(.rawCodable) }))
            addRegistryTypes(name: "Enums", types: allTypes.compactMap({ $0 as? CodeSimpleEnum<String> })) // TODO: also include CodeEnum, which would require extracting just the name
            addRegistryTypes(name: "Aliases", types: allTypes.compactMap({ $0 as? CodeTypeAlias }))

            module.types = [registryType] + module.types
        }

        // finally insert any root protocols we wanted to conform to
        module.types = conformances + module.types

        return module
    }

}

extension CodeNamedType {
    func purgeTypes<T : CodeNamedType & Hashable>(_ purge: Set<T>) -> CodeNamedType {
        let purgeCodeSet = purge.map(\.codeValue) // ### ugly, but generics prevent us from checking for equatable
        if var impl = self as? CodeStateType {
            impl.nestedTypes = impl.nestedTypes.filter({ !purgeCodeSet.contains($0.codeValue) }).map({ $0.purgeTypes(purge) })
            return impl
        } else if var alias = self as? CodeTypeAlias {
            alias.peerTypes = alias.peerTypes.filter({ !purgeCodeSet.contains($0.codeValue) }).map({ $0.purgeTypes(purge) })
            return alias
        } else {
            return self
        }
    }
}

public extension Schema {

    enum BracReferenceError : Error, CustomDebugStringConvertible {
        case referenceRequiredRoot(String)
        case referenceMustBeRelativeToCurrentDocument(String)
        case referenceMustBeRelativeToDocumentRoot(String)
        case refWithoutAdditionalProperties(String)
        case referenceNotFound(String)

        public var debugDescription : String {
            switch self {
            case .referenceRequiredRoot(let str): return "ReferenceRequiredRoot: \(str)"
            case .referenceMustBeRelativeToCurrentDocument(let str): return "ReferenceMustBeRelativeToCurrentDocument: \(str)"
            case .referenceMustBeRelativeToDocumentRoot(let str): return "ReferenceMustBeRelativeToDocumentRoot: \(str)"
            case .refWithoutAdditionalProperties(let str): return "RefWithoutAdditionalProperties: \(str)"
            case .referenceNotFound(let str): return "ReferenceNotFound: \(str)"
            }
        }
    }

    /// Support for JSON $ref <http://tools.ietf.org/html/draft-pbryan-zyp-json-ref-03>
    func resolve(_ path: String) throws -> Schema {
        var parts = path.split(whereSeparator: { $0 == "/" }).map { String($0) }
//        print("parts: \(parts)")
        if parts.isEmpty { throw BracReferenceError.referenceRequiredRoot(path) }
        let first = parts.remove(at: 0)
        if first != "#" {  throw BracReferenceError.referenceMustBeRelativeToCurrentDocument(path) }
        if parts.isEmpty { throw BracReferenceError.referenceRequiredRoot(path) }
        let root = parts.remove(at: 0)
        if _additionalProperties.isEmpty { throw BracReferenceError.refWithoutAdditionalProperties(path) }
        guard var json = _additionalProperties[root] else { throw BracReferenceError.referenceNotFound(path) }
        for part in parts {
            guard let next: Bric = json[part] else { throw BracReferenceError.referenceNotFound(path) }
            json = next
        }

        return try Schema.bracDecoded(bric: json)
    }

    /// Parse the given JSON info an array of resolved schema references, maintaining property order from the source JSON
    static func parse(_ source: String, rootName: String?) throws -> [(String, Schema)] {
        return try generate(impute(source), rootName: rootName)
    }

    static func generate(_ json: Bric, rootName: String?) throws -> [(String, Schema)] {
        let refmap = try json.resolve()

        var refschema : [String : Schema] = [:]

        var schemas: [(String, Schema)] = []
        for (key, value) in refmap {
            let subschema = try Schema.bracDecoded(bric: value)
            refschema[key] = subschema
            schemas.append((key, subschema))
        }

        let schema = try Schema.bracDecoded(bric: json)
        if let rootName = rootName {
            schemas.append((rootName, schema))
        }
        return schemas
    }

    /// Parses the given JSON and injects the property ordering attribute based on the underlying source
    static func impute(_ source: String) throws -> Bric {
        var fidelity = try FidelityBricolage.parse(source)
        fidelity = imputePropertyOrdering(fidelity)
        return fidelity.bric()
    }


    /// Walk through the raw bricolage and add in the "propertyOrder" prop so that the schema generator
    /// can use the same ordering that appears in the raw JSON schema
    fileprivate static func imputePropertyOrdering(_ bc: FidelityBricolage) -> FidelityBricolage {
        switch bc {
        case .arr(let arr):
            return .arr(arr.map(imputePropertyOrdering))
        case .obj(let obj):
            var sub = FidelityBricolage.createObject()

            for (key, value) in obj {
                sub.append((key, imputePropertyOrdering(value)))
                // if the key is "properties" then also add a "propertyOrder" property with the order that the props appear in the raw JSON
                if case .obj(let dict) = value, !dict.isEmpty && String(String.UnicodeScalarView() + key) == "properties" {
                    // ### FIXME: we hack in a check for "type" to determine if we are in a schema element and not,
                    //  e.g., another properties list, but this will fail if there is an actual property named "type"
                    if bc.bric()["type"] == "object" {
                        let ordering = dict.map(\.0)
                        sub.append((FidelityBricolage.StrType("propertyOrder".unicodeScalars), FidelityBricolage.arr(ordering.map(FidelityBricolage.str))))
                    }
                }
            }
            return .obj(sub)
        default:
            return bc
        }
    }

}

private let CurioUsage = [
    "Usage: cat <schema.json> | curio <arguments> | xcrun -sdk macosx swiftc -parse -",
    "Parameters:",
    "  -name: The name of the top-level type to be generated",
    "  -defs: The internal path to definitions (default: #/definitions/)",
    "  -maxdirect: The maximum number of properties before making them Indirect",
    "  -useOneOfEnums: Whether to collapse oneOfs into OneOf enum types",
    "  -useAllOfEnums: Whether to collapse allOfs into AllOf sum types",
    "  -useAnyOfEnums: Whether to collapse anyOfs into AnyOf sum types",
    "  -anyOfAsOneOf: Whether to treat AnyOf elements as OneOf elements",
    "  -rename: A renaming mapping",
    "  -import: Additional imports at the top of the generated source",
    "  -access: Default access (public, private, internal, or default)",
    "  -typetype: Generated type (struct or class)"
    ].joined(separator: "\n")

extension Curio {
    public static func runWithArguments(_ arguments: [String]) throws {
        var args = arguments.makeIterator()
        _ = args.next() ?? "curio" // cmdname


        struct UsageError : Error {
            let msg: String

            init(_ msg: String) {
                self.msg = msg + "\n" + CurioUsage
            }
        }

        var modelName: String? = nil
        var accessType: String? = "public"
        var renames: [String : String] = [:]
        var imports: [String] = ["BricBrac"]
        var maxdirect: Int?
        var typeType: String?
        var indirectEnums: Bool?
        var useOneOfEnums: Bool?
        var useAllOfEnums: Bool?
        var useAnyOfEnums: Bool?
        var anyOfAsOneOf: Bool?
        var generateEquals: Bool?
        var generateHashable: Bool?
        var generateCodable: Bool?
        var promoteIdenticalTypes: Bool?

        while let arg = args.next() {
            switch arg {
            case "-help":
                print(CurioUsage)
                return
            case "-name":
                modelName = args.next()
            case "-maxdirect":
                maxdirect = Int(args.next() ?? "")
            case "-rename":
                renames[args.next() ?? ""] = args.next()
            case "-import":
                imports.append(args.next() ?? "")
            case "-access":
                accessType = args.next()
            case "-typetype":
                typeType = String(args.next() ?? "")
            case "-indirectEnums":
                indirectEnums = (args.next() ?? "true").hasPrefix("t") == true ? true : false
            case "-useOneOfEnums":
                useOneOfEnums = (args.next() ?? "true").hasPrefix("t") == true ? true : false
            case "-useAllOfEnums":
                useAllOfEnums = (args.next() ?? "true").hasPrefix("t") == true ? true : false
            case "-useAnyOfEnums":
                useAnyOfEnums = (args.next() ?? "true").hasPrefix("t") == true ? true : false
            case "-anyOfAsOneOf":
                anyOfAsOneOf = (args.next() ?? "true").hasPrefix("t") == true ? true : false
            case "-generateEquals":
                generateEquals = (args.next() ?? "true").hasPrefix("t") == true ? true : false
            case "-generateHashable":
                generateHashable = (args.next() ?? "true").hasPrefix("t") == true ? true : false
            case "-generateCodable":
                generateCodable = (args.next() ?? "true").hasPrefix("t") == true ? true : false
            case "-promoteIdenticalTypes":
                promoteIdenticalTypes = (args.next() ?? "true").hasPrefix("t") == true ? true : false
            default:
                throw UsageError("Unrecognized argument: \(arg)")
            }
        }

        do {
            guard let modelName = modelName else {
                throw UsageError("Missing model name")
            }

            guard let accessType = accessType else {
                throw UsageError("Missing access type")
            }

            var access: CodeAccess
            switch accessType {
            case "public": access = .`public`
            case "private": access = .`private`
            case "internal": access = .`internal`
            case "default": access = .`default`
            default: throw UsageError("Unknown access type: \(accessType) (must be 'public', 'private', 'internal', or 'default')")
            }

            var curio = Curio()
            if let maxdirect = maxdirect { curio.indirectCountThreshold = maxdirect }
            if let indirectEnums = indirectEnums { curio.indirectEnums = indirectEnums }
            if let useOneOfEnums = useOneOfEnums { curio.useOneOfEnums = useOneOfEnums }
            if let useAllOfEnums = useAllOfEnums { curio.useAllOfEnums = useAllOfEnums }
            if let useAnyOfEnums = useAnyOfEnums { curio.useAnyOfEnums = useAnyOfEnums }
            if let anyOfAsOneOf = anyOfAsOneOf { curio.anyOfAsOneOf = anyOfAsOneOf }
            if let generateEquals = generateEquals { curio.generateEquals = generateEquals }
            if let generateHashable = generateHashable { curio.generateHashable = generateHashable }
            if let generateCodable = generateCodable { curio.generateCodable = generateCodable }
            if let promoteIdenticalTypes = promoteIdenticalTypes { curio.promoteIdenticalTypes = promoteIdenticalTypes }

            if let typeType = typeType {
                switch typeType {
                case "struct": curio.generateValueTypes = true
                case "class": curio.generateValueTypes = false
                default: throw UsageError("Unknown type type: \(typeType) (must be 'struct' or 'class')")
                }
            }
            
            curio.accessor = { _ in access }
            curio.renamer = { (parents, id) in
                let key = (parents + [id]).joined(separator: ".")
                return renames[id] ?? renames[key]
            }
            
            
            //debugPrint("Reading schema file from standard input")
            var src: String = ""
            while let line = readLine(strippingNewline: false) {
                src += line
            }
            
            let schemas = try Schema.parse(src, rootName: modelName)
            let module = try curio.assemble(schemas)

            module.imports = imports

            let emitter = CodeEmitter(stream: "")
            module.emit(emitter)
            
            let code = emitter.stream
            print(code)
        }
    }
}

/// Standard types
extension CodeExternalType {
    static let string = CodeExternalType("String")
    static let number = CodeExternalType("Double")
    static let integer = CodeExternalType("Int")
    static let boolean = CodeExternalType("Bool")
    static let void = CodeExternalType("Void")
    static let encoder = CodeExternalType("Encoder")
    static let decoder = CodeExternalType("Decoder")
}

/// BricBrac types
extension CodeExternalType {
    static let null = CodeExternalType("ExplicitNull")
    static let hollow = CodeExternalType("HollowBric")
    static let bric = CodeExternalType("Bric", defaultValue: "nil")
    static let array = CodeExternalType("Array", generics: [CodeExternalType.bric], defaultValue: "[]")
    static let object = CodeExternalType("Dictionary", generics: [CodeExternalType.string, CodeExternalType.bric], defaultValue: "[:]")
}

/// Standard protocols
extension CodeProtocol {
    static let codable = CodeProtocol(name: "Codable")
    static let keyedCodable = CodeProtocol(name: "KeyedCodable")
    static let codingKey = CodeProtocol(name: "CodingKey")
    static let caseIterable = CodeProtocol(name: "CaseIterable")
    static let identifiable = CodeProtocol(name: "Identifiable")
    static let equatable = CodeProtocol(name: "Equatable")
    static let hashable = CodeProtocol(name: "Hashable")
    static let rawRepresentable = CodeProtocol(name: "RawRepresentable")
    static let rawCodable = CodeProtocol(name: "RawCodable")
}

/// BricBrac protocols
extension CodeProtocol {
    static let bracable = CodeProtocol(name: "Bracable")
    static let bricable = CodeProtocol(name: "Bricable")
}

