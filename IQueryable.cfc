interface {

	query function executeSelect(required lib.sql.SelectStatement selectStatement, required numeric limit, required numeric offset);

	boolean function fieldExists(required string fieldName);

	boolean function fieldIsFilterable(required string fieldName);

	string function getFieldList();

	string function getFieldSQL(required string fieldName);

	string function getFieldSQLType(required string fieldName);

	string function getIdentifierField();

	lib.sql.SelectStatement function select(string fieldList = "*");

}