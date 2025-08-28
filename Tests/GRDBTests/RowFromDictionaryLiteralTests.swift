import XCTest
import GRDB

private enum CustomValue : Int, DatabaseValueConvertible, Equatable {
    case a = 0
    case b = 1
    case c = 2
}

class RowFromDictionaryLiteralTests : RowTestCase {
    
    func testRowAsSequence() {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        
        var columnNames = Set<String>()
        var ints = Set<Int>()
        var bools = Set<Bool>()
        for (columnName, dbValue) in row {
            columnNames.insert(columnName)
            ints.insert(Int.fromDatabaseValue(dbValue)!)
            bools.insert(Bool.fromDatabaseValue(dbValue)!)
        }
        
        XCTAssertEqual(columnNames, ["a", "b", "c"])
        XCTAssertEqual(ints, [0, 1, 2])
        XCTAssertEqual(bools, [false, true, true])
    }
    
    func testColumnOrderIsPreserved() {
        // Paramount for tests
        let row: Row = ["a": 0, "i": 8, "b": 1, "h": 7, "c": 2, "g": 6, "d": 3, "f": 5, "e": 4]
        XCTAssertEqual(Array(row.columnNames), ["a", "i", "b", "h", "c", "g", "d", "f", "e"])
    }
    
    func testDuplicateColumnNames() {
        // Paramount for tests
        let row: Row = ["a": 0, "a": 1]
        XCTAssertEqual(Array(row.columnNames), ["a", "a"])
        XCTAssertEqual(row["a"] as Int, 0)
    }
    
    func testRowValueAtIndex() throws {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        
        let aIndex = row.distance(from: row.startIndex, to: row.firstIndex(where: { (column, value) in column == "a" })!)
        let bIndex = row.distance(from: row.startIndex, to: row.firstIndex(where: { (column, value) in column == "b" })!)
        let cIndex = row.distance(from: row.startIndex, to: row.firstIndex(where: { (column, value) in column == "c" })!)
        
        // Raw extraction
        assertRowRawValueEqual(row, index: aIndex, value: 0 as Int64)
        assertRowRawValueEqual(row, index: bIndex, value: 1 as Int64)
        assertRowRawValueEqual(row, index: cIndex, value: 2 as Int64)
        
        // DatabaseValueConvertible & StatementColumnConvertible
        try assertRowConvertedValueEqual(row, index: aIndex, value: 0 as Int)
        try assertRowConvertedValueEqual(row, index: bIndex, value: 1 as Int)
        try assertRowConvertedValueEqual(row, index: cIndex, value: 2 as Int)
        
        // DatabaseValueConvertible
        try assertRowConvertedValueEqual(row, index: aIndex, value: CustomValue.a)
        try assertRowConvertedValueEqual(row, index: bIndex, value: CustomValue.b)
        try assertRowConvertedValueEqual(row, index: cIndex, value: CustomValue.c)
        
        // Expect fatal error:
        //
        // row[-1]
        // row[3]
    }
    
    func testRowValueNamed() throws {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        
        // Raw extraction
        assertRowRawValueEqual(row, name: "a", value: 0 as Int64)
        assertRowRawValueEqual(row, name: "b", value: 1 as Int64)
        assertRowRawValueEqual(row, name: "c", value: 2 as Int64)
        
        // DatabaseValueConvertible & StatementColumnConvertible
        try assertRowConvertedValueEqual(row, name: "a", value: 0 as Int)
        try assertRowConvertedValueEqual(row, name: "b", value: 1 as Int)
        try assertRowConvertedValueEqual(row, name: "c", value: 2 as Int)
        
        // DatabaseValueConvertible
        try assertRowConvertedValueEqual(row, name: "a", value: CustomValue.a)
        try assertRowConvertedValueEqual(row, name: "b", value: CustomValue.b)
        try assertRowConvertedValueEqual(row, name: "c", value: CustomValue.c)
    }
    
    func testRowValueFromColumn() throws {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        
        // Raw extraction
        assertRowRawValueEqual(row, column: Column("a"), value: 0 as Int64)
        assertRowRawValueEqual(row, column: Column("b"), value: 1 as Int64)
        assertRowRawValueEqual(row, column: Column("c"), value: 2 as Int64)
        
        // DatabaseValueConvertible & StatementColumnConvertible
        try assertRowConvertedValueEqual(row, column: Column("a"), value: 0 as Int)
        try assertRowConvertedValueEqual(row, column: Column("b"), value: 1 as Int)
        try assertRowConvertedValueEqual(row, column: Column("c"), value: 2 as Int)
        
        // DatabaseValueConvertible
        try assertRowConvertedValueEqual(row, column: Column("a"), value: CustomValue.a)
        try assertRowConvertedValueEqual(row, column: Column("b"), value: CustomValue.b)
        try assertRowConvertedValueEqual(row, column: Column("c"), value: CustomValue.c)
    }
    
    func testWithUnsafeData() throws {
        do {
            let data = "foo".data(using: .utf8)!
            let row: Row = ["a": data]
            
            try row.withUnsafeData(atIndex: 0) { XCTAssertEqual($0, data) }
            try row.withUnsafeData(named: "a") { XCTAssertEqual($0, data) }
            try row.withUnsafeData(at: Column("a")) { XCTAssertEqual($0, data) }
            
            try row.withUnsafeData(named: "missing") { XCTAssertNil($0) }
            try row.withUnsafeData(at: Column("missing")) { XCTAssertNil($0) }
        }
        do {
            let emptyData = Data()
            let row: Row = ["a": emptyData]
            
            try row.withUnsafeData(atIndex: 0) { XCTAssertEqual($0, emptyData) }
            try row.withUnsafeData(named: "a") { XCTAssertEqual($0, emptyData) }
            try row.withUnsafeData(at: Column("a")) { XCTAssertEqual($0, emptyData) }
        }
        do {
            let row: Row = ["a": nil]
            
            try row.withUnsafeData(atIndex: 0) { XCTAssertNil($0) }
            try row.withUnsafeData(named: "a") { XCTAssertNil($0) }
            try row.withUnsafeData(at: Column("a")) { XCTAssertNil($0) }
        }
    }
    
    func testRowDatabaseValueAtIndex() throws {
        let row: Row = ["null": nil, "int64": 1, "double": 1.1, "string": "foo", "blob": "SQLite".data(using: .utf8)]
        
        let nullIndex = row.distance(from: row.startIndex, to: row.firstIndex(where: { (column, value) in column == "null" })!)
        let int64Index = row.distance(from: row.startIndex, to: row.firstIndex(where: { (column, value) in column == "int64" })!)
        let doubleIndex = row.distance(from: row.startIndex, to: row.firstIndex(where: { (column, value) in column == "double" })!)
        let stringIndex = row.distance(from: row.startIndex, to: row.firstIndex(where: { (column, value) in column == "string" })!)
        let blobIndex = row.distance(from: row.startIndex, to: row.firstIndex(where: { (column, value) in column == "blob" })!)
        
        guard case .null = (row[nullIndex] as DatabaseValue).storage else { XCTFail(); return }
        guard case .int64(let int64) = (row[int64Index] as DatabaseValue).storage, int64 == 1 else { XCTFail(); return }
        guard case .double(let double) = (row[doubleIndex] as DatabaseValue).storage, double == 1.1 else { XCTFail(); return }
        guard case .string(let string) = (row[stringIndex] as DatabaseValue).storage, string == "foo" else { XCTFail(); return }
        guard case .blob(let data) = (row[blobIndex] as DatabaseValue).storage, data == "SQLite".data(using: .utf8) else { XCTFail(); return }
    }
    
    func testRowDatabaseValueNamed() throws {
        let row: Row = ["null": nil, "int64": 1, "double": 1.1, "string": "foo", "blob": "SQLite".data(using: .utf8)]
        
        guard case .null = (row["null"] as DatabaseValue).storage else { XCTFail(); return }
        guard case .int64(let int64) = (row["int64"] as DatabaseValue).storage, int64 == 1 else { XCTFail(); return }
        guard case .double(let double) = (row["double"] as DatabaseValue).storage, double == 1.1 else { XCTFail(); return }
        guard case .string(let string) = (row["string"] as DatabaseValue).storage, string == "foo" else { XCTFail(); return }
        guard case .blob(let data) = (row["blob"] as DatabaseValue).storage, data == "SQLite".data(using: .utf8) else { XCTFail(); return }
    }
    
    func testRowCount() {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        XCTAssertEqual(row.count, 3)
    }
    
    func testRowColumnNames() {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        XCTAssertEqual(Array(row.columnNames).sorted(), ["a", "b", "c"])
    }
    
    func testRowDatabaseValues() {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        XCTAssertEqual(row.databaseValues.sorted { Int.fromDatabaseValue($0)! < Int.fromDatabaseValue($1)! }, [0.databaseValue, 1.databaseValue, 2.databaseValue])
    }
    
    func testRowIsCaseInsensitive() {
        let row: Row = ["name": "foo"]
        XCTAssertEqual(row["name"] as DatabaseValue, "foo".databaseValue)
        XCTAssertEqual(row["NAME"] as DatabaseValue, "foo".databaseValue)
        XCTAssertEqual(row["NaMe"] as DatabaseValue, "foo".databaseValue)
        XCTAssertEqual(row["name"] as String, "foo")
        XCTAssertEqual(row["NAME"] as String, "foo")
        XCTAssertEqual(row["NaMe"] as String, "foo")
    }
    
    func testMissingColumn() {
        let row: Row = ["name": "foo"]
        XCTAssertFalse(row.hasColumn("missing"))
        XCTAssertTrue(row["missing"] as DatabaseValue? == nil)
        XCTAssertTrue(row["missing"] == nil)
    }
    
    func testRowHasColumnIsCaseInsensitive() {
        let row: Row = ["nAmE": "foo", "foo": 1]
        XCTAssertTrue(row.hasColumn("name"))
        XCTAssertTrue(row.hasColumn("NAME"))
        XCTAssertTrue(row.hasColumn("Name"))
        XCTAssertTrue(row.hasColumn("NaMe"))
        XCTAssertTrue(row.hasColumn("foo"))
        XCTAssertTrue(row.hasColumn("Foo"))
        XCTAssertTrue(row.hasColumn("FOO"))
    }
    
    func testScopes() {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        XCTAssertTrue(row.scopes.isEmpty)
        XCTAssertTrue(row.scopes["missing"] == nil)
        XCTAssertTrue(row.scopesTree["missing"] == nil)
    }
    
    func testCopy() {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        
        let copiedRow = row.copy()
        XCTAssertEqual(copiedRow.count, 3)
        XCTAssertEqual(copiedRow["a"] as Int, 0)
        XCTAssertEqual(copiedRow["b"] as Int, 1)
        XCTAssertEqual(copiedRow["c"] as Int, 2)
    }
    
    func testEqualityWithCopy() {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        
        let copiedRow = row.copy()
        XCTAssertEqual(row, copiedRow)
    }
    
    func testDescription() throws {
        let row: Row = ["a": 0, "b": 1, "c": 2]
        XCTAssertEqual(row.description, "[a:0 b:1 c:2]")
        XCTAssertEqual(row.debugDescription, "[a:0 b:1 c:2]")
    }
    
    func testCoalesce() throws {
        let rows: [Row] = [
            ["nickname": "Artie", "name": "Arthur"],
            ["nickname": nil, "name": "Jacob"],
            ["nickname": nil, "name": nil],
        ]
        let values = rows.map { row in
            [
                row.coalesce(Array<String>()) as String?,
                row.coalesce(["nickname"]) as String?,
                row.coalesce(["nickname", "name"]) as String?,
                row.coalesce([Column("nickname"), Column("name")]) as String?,
            ]
        }
        XCTAssertEqual(values, [
            [nil, "Artie", "Artie", "Artie"],
            [nil, nil, "Jacob", "Jacob"],
            [nil, nil, nil, nil],
        ])
    }
}
