component accessors = "true" extends = "FilterStatement" {

	property name = "upsertFields" type = "struct" setter = "false";

	UpsertStatement function init(required IWritable writable, required struct fields) {
		variables.upsertFields = {};

		for(local.field in arguments.fields) {
			if(arguments.writable.fieldExists(local.field)) {
				variables.upsertFields[local.field] = {
					cfsqltype: arguments.writable.getFieldSQLType(local.field),
					null: !structKeyExists(arguments.fields, local.field) || len(arguments.fields[local.field]) == 0,
					value: structKeyExists(arguments.fields, local.field) ? arguments.fields[local.field] : ""
				};
			} else {
				throw(type = "UndefinedUpsertField", message = "The field '#local.field#' does not exist");
			}
		}

		return super.init(arguments.writable);
	}

	void function execute() {
		getQueryable().executeUpsert(this);
	}

}