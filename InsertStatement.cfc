component accessors = "true" {

	property name = "insertFields" type = "struct" setter = "false";
	property name = "writable" type = "IWritable" setter = "false";

	InsertStatement function init(required IWritable writable, required struct fields) {
		variables.writable = arguments.writable;
		variables.insertFields = {};

		for(local.field in arguments.fields) {
			if(arguments.writable.fieldExists(local.field)) {
				variables.insertFields[local.field] = {
						cfsqltype: arguments.writable.getFieldSQLType(local.field),
						null: !structKeyExists(arguments.fields, local.field) || len(arguments.fields[local.field]) == 0,
						value: structKeyExists(arguments.fields, local.field) ? arguments.fields[local.field] : ""
					};
			} else {
				throw(type = "UndefinedInsertField", message = "The field '#local.field#' does not exist");
			}
		}

		return this;
	}

	void function execute() {
		getWritable().executeInsert(this);
	}

}