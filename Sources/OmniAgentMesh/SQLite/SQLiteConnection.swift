import CSQLite
import Foundation

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteConnectionError: Error, CustomStringConvertible {
    case openDatabase(String)
    case prepareStatement(String)
    case bindParameter(String)
    case step(String)

    var description: String {
        switch self {
        case .openDatabase(let message),
             .prepareStatement(let message),
             .bindParameter(let message),
             .step(let message):
            return message
        }
    }
}

enum SQLiteValue: Sendable {
    case integer(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null

    var int64Value: Int64? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .text(let value) = self else { return nil }
        return value
    }

    var dataValue: Data? {
        switch self {
        case .blob(let value):
            return value
        case .text(let value):
            return Data(value.utf8)
        default:
            return nil
        }
    }
}

struct SQLiteRow: Sendable {
    fileprivate var values: [String: SQLiteValue]

    subscript(_ column: String) -> SQLiteValue? {
        values[column]
    }
}

final class SQLiteConnection: @unchecked Sendable {
    private let fileURL: URL
    private var handle: OpaquePointer?

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            fileURL.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database at \(fileURL.path())"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteConnectionError.openDatabase(message)
        }

        self.handle = database
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA busy_timeout=5000;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else {
            throw SQLiteConnectionError.step(lastErrorMessage())
        }
    }

    func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }

            guard result == SQLITE_ROW else {
                throw SQLiteConnectionError.step(lastErrorMessage())
            }

            rows.append(extractRow(from: statement))
        }

        return rows
    }

    func scalarInt(_ sql: String, bindings: [SQLiteValue] = []) throws -> Int64? {
        try query(sql, bindings: bindings).first?["value"]?.int64Value
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try body()
            try execute("COMMIT TRANSACTION;")
            return result
        } catch {
            try? execute("ROLLBACK TRANSACTION;")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let handle else {
            throw SQLiteConnectionError.openDatabase("SQLite database closed at \(fileURL.path())")
        }

        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw SQLiteConnectionError.prepareStatement(lastErrorMessage())
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32

            switch value {
            case .integer(let number):
                result = sqlite3_bind_int64(statement, index, number)
            case .double(let number):
                result = sqlite3_bind_double(statement, index, number)
            case .text(let string):
                result = string.withCString { characters in
                    sqlite3_bind_text(statement, index, characters, -1, sqliteTransientDestructor)
                }
            case .blob(let data):
                result = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), sqliteTransientDestructor)
                }
            case .null:
                result = sqlite3_bind_null(statement, index)
            }

            guard result == SQLITE_OK else {
                throw SQLiteConnectionError.bindParameter(lastErrorMessage())
            }
        }
    }

    private func extractRow(from statement: OpaquePointer?) -> SQLiteRow {
        let columnCount = Int(sqlite3_column_count(statement))
        var values: [String: SQLiteValue] = [:]
        values.reserveCapacity(columnCount)

        for columnIndex in 0..<columnCount {
            let rawName = sqlite3_column_name(statement, Int32(columnIndex))
            let name = rawName.map(String.init(cString:)) ?? "column_\(columnIndex)"
            let type = sqlite3_column_type(statement, Int32(columnIndex))

            switch type {
            case SQLITE_INTEGER:
                values[name] = .integer(sqlite3_column_int64(statement, Int32(columnIndex)))
            case SQLITE_FLOAT:
                values[name] = .double(sqlite3_column_double(statement, Int32(columnIndex)))
            case SQLITE_TEXT:
                if let rawValue = sqlite3_column_text(statement, Int32(columnIndex)) {
                    values[name] = .text(String(cString: rawValue))
                } else {
                    values[name] = .null
                }
            case SQLITE_BLOB:
                let byteCount = Int(sqlite3_column_bytes(statement, Int32(columnIndex)))
                if let rawValue = sqlite3_column_blob(statement, Int32(columnIndex)), byteCount > 0 {
                    values[name] = .blob(Data(bytes: rawValue, count: byteCount))
                } else {
                    values[name] = .blob(Data())
                }
            default:
                values[name] = .null
            }
        }

        return SQLiteRow(values: values)
    }

    private func lastErrorMessage() -> String {
        guard let handle else {
            return "SQLite database is unavailable."
        }
        return String(cString: sqlite3_errmsg(handle))
    }
}
