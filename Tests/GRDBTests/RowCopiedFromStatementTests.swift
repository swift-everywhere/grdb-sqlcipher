import XCTest
import GRDB

private enum CustomValue : Int, DatabaseValueConvertible, Equatable {
    case a = 0
    case b = 1
    case c = 2
}

class RowCopiedFromStatementTests: RowTestCase {
    
    func testRowAsSequence() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.execute(sql: "CREATE TABLE ints (a INTEGER, b INTEGER, c INTEGER)")
            try db.execute(sql: "INSERT INTO ints (a,b,c) VALUES (0, 1, 2)")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM ints")!
            
            var columnNames = [String]()
            var ints = [Int]()
            var bools = [Bool]()
            for (columnName, dbValue) in row {
                columnNames.append(columnName)
                ints.append(Int.fromDatabaseValue(dbValue)!)
                bools.append(Bool.fromDatabaseValue(dbValue)!)
            }
            
            XCTAssertEqual(columnNames, ["a", "b", "c"])
            XCTAssertEqual(ints, [0, 1, 2])
            XCTAssertEqual(bools, [false, true, true])
        }
    }

    func testRowValueAtIndex() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.execute(sql: "CREATE TABLE ints (a INTEGER, b INTEGER, c INTEGER)")
            try db.execute(sql: "INSERT INTO ints (a,b,c) VALUES (0, 1, 2)")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM ints")!
            
            // Raw extraction
            assertRowRawValueEqual(row, index: 0, value: 0 as Int64)
            assertRowRawValueEqual(row, index: 1, value: 1 as Int64)
            assertRowRawValueEqual(row, index: 2, value: 2 as Int64)
            
            // DatabaseValueConvertible & StatementColumnConvertible
            try assertRowConvertedValueEqual(row, index: 0, value: 0 as Int)
            try assertRowConvertedValueEqual(row, index: 1, value: 1 as Int)
            try assertRowConvertedValueEqual(row, index: 2, value: 2 as Int)
            
            // DatabaseValueConvertible
            try assertRowConvertedValueEqual(row, index: 0, value: CustomValue.a)
            try assertRowConvertedValueEqual(row, index: 1, value: CustomValue.b)
            try assertRowConvertedValueEqual(row, index: 2, value: CustomValue.c)
            
            // Expect fatal error:
            //
            // row[-1]
            // row[3]
        }
    }

    func testRowValueNamed() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.execute(sql: "CREATE TABLE ints (a INTEGER, b INTEGER, c INTEGER)")
            try db.execute(sql: "INSERT INTO ints (a,b,c) VALUES (0, 1, 2)")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM ints")!
            
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
    }

    func testRowValueFromColumn() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.execute(sql: "CREATE TABLE ints (a INTEGER, b INTEGER, c INTEGER)")
            try db.execute(sql: "INSERT INTO ints (a,b,c) VALUES (0, 1, 2)")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM ints")!
            
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
    }

    func testWithUnsafeData() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let data = "foo".data(using: .utf8)!
            let emptyData = Data()
            let row = try Row.fetchOne(db, sql: "SELECT ? AS a, ? AS b, ? AS c", arguments: [data, emptyData, nil])!
            
            try row.withUnsafeData(atIndex: 0) { XCTAssertEqual($0, data) }
            try row.withUnsafeData(named: "a") { XCTAssertEqual($0, data) }
            try row.withUnsafeData(at: Column("a")) { XCTAssertEqual($0, data) }
            
            try row.withUnsafeData(atIndex: 1) { XCTAssertEqual($0, emptyData) }
            try row.withUnsafeData(named: "b") { XCTAssertEqual($0, emptyData) }
            try row.withUnsafeData(at: Column("b")) { XCTAssertEqual($0, emptyData) }
            
            try row.withUnsafeData(atIndex: 2) { XCTAssertNil($0) }
            try row.withUnsafeData(named: "c") { XCTAssertNil($0) }
            try row.withUnsafeData(at: Column("c")) { XCTAssertNil($0) }
            
            try row.withUnsafeData(named: "missing") { XCTAssertNil($0) }
            try row.withUnsafeData(at: Column("missing")) { XCTAssertNil($0) }
        }
    }

    func testRowDatabaseValueAtIndex() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let row = try Row.fetchOne(db, sql: "SELECT NULL, 1, 1.1, 'foo', x'53514C697465'")!
            
            guard case .null = (row[0] as DatabaseValue).storage else { XCTFail(); return }
            guard case .int64(let int64) = (row[1] as DatabaseValue).storage, int64 == 1 else { XCTFail(); return }
            guard case .double(let double) = (row[2] as DatabaseValue).storage, double == 1.1 else { XCTFail(); return }
            guard case .string(let string) = (row[3] as DatabaseValue).storage, string == "foo" else { XCTFail(); return }
            guard case .blob(let data) = (row[4] as DatabaseValue).storage, data == "SQLite".data(using: .utf8) else { XCTFail(); return }
        }
    }

    func testRowDatabaseValueNamed() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let row = try Row.fetchOne(db, sql: "SELECT NULL AS \"null\", 1 AS \"int64\", 1.1 AS \"double\", 'foo' AS \"string\", x'53514C697465' AS \"blob\"")!
            
            guard case .null = (row["null"] as DatabaseValue).storage else { XCTFail(); return }
            guard case .int64(let int64) = (row["int64"] as DatabaseValue).storage, int64 == 1 else { XCTFail(); return }
            guard case .double(let double) = (row["double"] as DatabaseValue).storage, double == 1.1 else { XCTFail(); return }
            guard case .string(let string) = (row["string"] as DatabaseValue).storage, string == "foo" else { XCTFail(); return }
            guard case .blob(let data) = (row["blob"] as DatabaseValue).storage, data == "SQLite".data(using: .utf8) else { XCTFail(); return }
        }
    }

    func testRowCount() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.execute(sql: "CREATE TABLE ints (a INTEGER, b INTEGER, c INTEGER)")
            try db.execute(sql: "INSERT INTO ints (a,b,c) VALUES (0, 1, 2)")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM ints")!
            
            XCTAssertEqual(row.count, 3)
        }
    }

    func testRowColumnNames() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.execute(sql: "CREATE TABLE ints (a INTEGER, b INTEGER, c INTEGER)")
            try db.execute(sql: "INSERT INTO ints (a,b,c) VALUES (0, 1, 2)")
            let row = try Row.fetchOne(db, sql: "SELECT a, b, c FROM ints")!
            
            XCTAssertEqual(Array(row.columnNames), ["a", "b", "c"])
        }
    }

    func testRowDatabaseValues() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.execute(sql: "CREATE TABLE ints (a INTEGER, b INTEGER, c INTEGER)")
            try db.execute(sql: "INSERT INTO ints (a,b,c) VALUES (0, 1, 2)")
            let row = try Row.fetchOne(db, sql: "SELECT a, b, c FROM ints")!
            
            XCTAssertEqual(Array(row.databaseValues), [0.databaseValue, 1.databaseValue, 2.databaseValue])
        }
    }

    func testRowIsCaseInsensitive() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let row = try Row.fetchOne(db, sql: "SELECT 'foo' AS nAmE")!
            XCTAssertEqual(row["name"] as DatabaseValue, "foo".databaseValue)
            XCTAssertEqual(row["NAME"] as DatabaseValue, "foo".databaseValue)
            XCTAssertEqual(row["NaMe"] as DatabaseValue, "foo".databaseValue)
            XCTAssertEqual(row["name"] as String, "foo")
            XCTAssertEqual(row["NAME"] as String, "foo")
            XCTAssertEqual(row["NaMe"] as String, "foo")
        }
    }

    func testRowIsCaseInsensitiveAndReturnsLeftmostMatchingColumn() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let row = try Row.fetchOne(db, sql: "SELECT 1 AS name, 2 AS NAME")!
            XCTAssertEqual(row["name"] as DatabaseValue, 1.databaseValue)
            XCTAssertEqual(row["NAME"] as DatabaseValue, 1.databaseValue)
            XCTAssertEqual(row["NaMe"] as DatabaseValue, 1.databaseValue)
            XCTAssertEqual(row["name"] as Int, 1)
            XCTAssertEqual(row["NAME"] as Int, 1)
            XCTAssertEqual(row["NaMe"] as Int, 1)
        }
    }

    func testMissingColumn() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let row = try Row.fetchOne(db, sql: "SELECT 'foo' AS name")!
            
            XCTAssertFalse(row.hasColumn("missing"))
            XCTAssertTrue(row["missing"] as DatabaseValue? == nil)
            XCTAssertTrue(row["missing"] == nil)
        }
    }

    func testRowHasColumnIsCaseInsensitive() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let row = try Row.fetchOne(db, sql: "SELECT 'foo' AS nAmE, 1 AS foo")!
            XCTAssertTrue(row.hasColumn("name"))
            XCTAssertTrue(row.hasColumn("NAME"))
            XCTAssertTrue(row.hasColumn("Name"))
            XCTAssertTrue(row.hasColumn("NaMe"))
            XCTAssertTrue(row.hasColumn("foo"))
            XCTAssertTrue(row.hasColumn("Foo"))
            XCTAssertTrue(row.hasColumn("FOO"))
        }
    }

    func testScopes() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let row = try Row.fetchOne(db, sql: "SELECT 'foo' AS nAmE, 1 AS foo")!
            XCTAssertTrue(row.scopes.isEmpty)
            XCTAssertTrue(row.scopes["missing"] == nil)
            XCTAssertTrue(row.scopesTree["missing"] == nil)
        }
    }

    func testCopy() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.execute(sql: "CREATE TABLE ints (a INTEGER, b INTEGER, c INTEGER)")
            try db.execute(sql: "INSERT INTO ints (a,b,c) VALUES (0, 1, 2)")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM ints")!
            
            let copiedRow = row.copy()
            XCTAssertEqual(copiedRow.count, 3)
            XCTAssertEqual(copiedRow["a"] as Int, 0)
            XCTAssertEqual(copiedRow["b"] as Int, 1)
            XCTAssertEqual(copiedRow["c"] as Int, 2)
        }
    }

    func testEqualityWithCopy() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.execute(sql: "CREATE TABLE ints (a INTEGER, b INTEGER, c INTEGER)")
            try db.execute(sql: "INSERT INTO ints (a,b,c) VALUES (0, 1, 2)")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM ints")!
            
            let copiedRow = row.copy()
            XCTAssertEqual(row, copiedRow)
        }
    }
    
    func testDescription() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let row = try Row.fetchOne(db, sql: "SELECT NULL AS \"null\", 1 AS \"int\", 1.1 AS \"double\", 'foo' AS \"string\", x'53514C697465' AS \"data\"")!
            XCTAssertEqual(row.description, "[null:NULL int:1 double:1.1 string:\"foo\" data:Data(6 bytes)]")
            XCTAssertEqual(row.debugDescription, "[null:NULL int:1 double:1.1 string:\"foo\" data:Data(6 bytes)]")
        }
    }
    
    func testCoalesce() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let values = try Row
                .fetchAll(db, sql: """
                    SELECT           'Artie' AS nickname, 'Arthur' AS name 
                    UNION ALL SELECT NULL, 'Jacob' 
                    UNION ALL SELECT NULL, NULL
                    """)
                .map { row in
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
}
