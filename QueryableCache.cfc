component implements = "lib.sql.IQueryable" {

	/*
		an extension of the IQueryable interface to leverage on top of a persistent searchable cache
		implementations:
		- https://github.com/DonorDrive/ehcache
		- https://github.com/DonorDrive/redis

		these methods assume that the identifierField defined will be furnished as a named argument (or in the case of putRow, a member of the furnished struct)

		this may make sense to implement as an Abstract component down the road...
	*/

	boolean function containsRow() {
		throw(type = "lib.sql.MethodNotImplementedException");
	}

	query function executeSelect(required lib.sql.SelectStatement selectStatement, required numeric limit, required numeric offset) {
		throw(type = "lib.sql.MethodNotImplementedException");
	}

	boolean function fieldExists(required string fieldName) {
		return variables.queryable.fieldExists(arguments.fieldName);
	}

	boolean function fieldIsFilterable(required string fieldName) {
		return variables.queryable.fieldIsFilterable(arguments.fieldName);
	}

	string function getFieldList() {
		return variables.queryable.getFieldList();
	}

	string function getFieldSQL(required string fieldName) {
		return "";
	}

	string function getFieldSQLType(required string fieldName) {
		return variables.queryable.getFieldSQLType(arguments.fieldName);
	}

	string function getIdentifierField() {
		return variables.queryable.getIdentifierField();
	}

	lib.sql.IQueryable function getQueryable() {
		return variables.queryable;
	}

	any function getRow() {
		throw(type = "lib.sql.MethodNotImplementedException");
	}

	string function getRowKey() {
		local.rowKey = getRowKeyMask();

		local.pos = find("{", local.rowKey);

		do {
			local.end = find("}", local.rowKey, local.pos);
			local.keyArg = mid(local.rowKey, local.pos + 1, local.end - local.pos - 1);
			local.rowKey = replace(local.rowKey, "{#local.keyArg#}", REReplace(arguments[local.keyArg], "[^A-Za-z0-9]", "", "all"));
			local.pos = find("{", local.rowKey);
		} while(local.pos > 0);

		return lCase(local.rowKey);
	}

	string function getRowKeyMask() {
		return variables.rowKeyMask;
	}


	void function putRow(required struct row) {
		throw(type = "lib.sql.MethodNotImplementedException");
	}

	void function removeRow() {
		throw(type = "lib.sql.MethodNotImplementedException");
	}

	void function seedFromQueryable(boolean overwrite = false, string where = "") {
		throw(type = "lib.sql.MethodNotImplementedException");
	}

	lib.sql.SelectStatement function select(string fieldList = "*") {
		return new lib.sql.SelectStatement(this).select(arguments.fieldList);
	}

	lib.sql.QueryableCache function setQueryable(required lib.sql.IQueryable queryable) {
		variables.queryable = arguments.queryable;

		return this;
	}

	lib.sql.QueryableCache function setRowKeyMask(required string rowKeyMask) {
		if(!structKeyExists(variables, "queryable")) {
			throw(type = "lib.ehcache.UndefinedQueryableException", message = "an IQueryable must be furnished before defining rowKeyMask");
		}

		local.rowKeyMask = listReduce(
			getFieldList(),
			function(result, keyField) {
				return replaceNoCase(arguments.result, "{#arguments.keyField#}", "");
			},
			arguments.rowKeyMask
		);

		if(find("{", local.rowKeyMask) || find("}", local.rowKeyMask)) {
			throw(type = "lib.ehcache.KeyMaskParsingException");
		} else if(local.rowKeyMask == arguments.rowKeyMask) {
			throw(type = "lib.ehcache.KeyMaskParsingException");
		}

		variables.rowKeyMask = lCase(arguments.rowKeyMask);

		return this;
	}

}