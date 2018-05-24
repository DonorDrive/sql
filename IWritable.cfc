interface extends = "IQueryable" {

	void function executeDelete(required lib.sql.DeleteStatement deleteStatement);

	void function executeInsert(required lib.sql.InsertStatement insertStatement);

	void function executeUpdate(required lib.sql.UpdateStatement updateStatement);

	void function executeUpsert(required lib.sql.UpsertStatement upsertStatement);

	lib.sql.DeleteStatement function delete();

	lib.sql.InsertStatement function insert(required struct fields);

	lib.sql.UpdateStatement function update(required struct fields);

	lib.sql.UpsertStatement function upsert(required struct fields);

}