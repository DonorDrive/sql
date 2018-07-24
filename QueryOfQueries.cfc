component accessors = "true" implements = "lib.sql.IQueryable,lib.sql.IWritable" {

	property name = "createdDateUTC" type = "date" setter = "false";
	property name = "identifierField" type = "string";

	QueryOfQueries function init(required query query) {
		variables.createdDateUTC = now();

		variables.query = arguments.query;

		return this;
	}

	lib.sql.DeleteStatement function delete() {
		return new DeleteStatement(this);
	}

	void function executeDelete(required lib.sql.DeleteStatement deleteStatement) {
		makeWritable();

		local.where = arguments.deleteStatement.getWhereSQL();

		if(local.where.len() == 0) {
			local.where = "WHERE 1 = 0";
		} else {
			// wrap the condition in a group-negation
			local.where = local.where.replace("WHERE ", "WHERE NOT (") & ")";
		}

		variables.query = queryExecute(
			"SELECT * FROM query " & local.where,
			arguments.deleteStatement.getParameters(),
			{ dbtype: "query" }
		);
	}

	void function executeInsert(required lib.sql.InsertStatement insertStatement) {
		makeWritable();

		// bring the insert fields over to a queryAddRow-friendly format
		local.insertFields = arguments.insertStatement.getInsertFields();
		local.row = {};

		for(local.field in local.insertFields) {
			if(listFindNoCase(variables.query.columnList, local.field)) {
				local.row[local.field] = local.insertFields[local.field].value;
			}
		}

		local.row._modifiedDateUTC = now();

		queryAddRow(variables.query, local.row);
	}

	void function executeUpdate(required lib.sql.UpdateStatement updateStatement) {
		makeWritable();

		local.updateRows = queryExecute(
				"SELECT #variables.identifierField# FROM query " & arguments.updateStatement.getWhereSQL(),
				arguments.updateStatement.getParameters(),
				{ dbtype: "query" }
			);

		if(local.updateRows.recordCount > 0) {
			// we may be updating a lot of rows... set now() to a var so we get a consistent update timestamp
			local.now = now();
			local.updateFields = arguments.updateStatement.getUpdateFields();

			for(local.row in local.updateRows) {
				// arrayFind is not performant at the scale this will be operating at
				local.rowNumber = variables.query[variables.identifierField].indexOf(local.row[variables.identifierField]) + 1;
				for(local.field in local.updateFields) {
					if(listFindNoCase(variables.query.columnList, local.field)) {
						querySetCell(variables.query, local.field, local.updateFields[local.field].value, local.rowNumber);
					}
				}

				querySetCell(variables.query, "_modifiedDateUTC", now());
			}
		}
	}

	void function executeUpsert(required lib.sql.UpsertStatement upsertStatement) {
		makeWritable();

		local.upsertRows = queryExecute(
				"SELECT #variables.identifierField# FROM query " & arguments.upsertStatement.getWhereSQL(),
				arguments.upsertStatement.getParameters(),
				{ dbtype: "query" }
			);

		if(local.upsertRows.recordCount == 0) {
			// bring the insert fields over to a queryAddRow-friendly format
			local.upsertFields = arguments.upsertStatement.getUpsertFields();
			local.row = {};

			for(local.field in local.upsertFields) {
				local.row[local.field] = local.upsertFields[local.field].value;
			}

			local.row._modifiedDateUTC = now();

			queryAddRow(variables.query, local.row);
		} else {
			local.upsertFields = arguments.upsertStatement.getUpsertFields();
			local.now = now();

			for(local.row in local.upsertRows) {
				local.rowNumber = variables.query[variables.identifierField].indexOf(local.row[variables.identifierField]) + 1;

				for(local.field in local.upsertFields) {
					querySetCell(variables.query, local.field, local.upsertFields[local.field].value, local.rowNumber);
				}

				querySetCell(variables.query, "_modifiedDateUTC", local.now, local.rowNumber);
			}
		}
	}

	query function executeSelect(required lib.sql.SelectStatement selectStatement, required numeric limit, required numeric offset) {
		var groupBySQL = arguments.selectStatement.getGroupBySQL();
		var orderBySQL = arguments.selectStatement.getOrderBySQL();
		var parameters = arguments.selectStatement.getParameters();
		var selectSQL = arguments.selectStatement.getSelectSQL();
		var whereSQL = arguments.selectStatement.getWhereSQL();

		// format our incoming SQL to circumvent QoQ's case-sensitivity
		if(parameters.len() > 0) {
			for(local.i = 1; local.i <= parameters.len(); local.i++) {
				if(parameters[local.i].cfsqltype CONTAINS "char") {
					// force the type so the prepared statement doesn't have a fit
					parameters[local.i].cfsqltype = "varchar";
					parameters[local.i].value = lCase(parameters[local.i].value);
				}
			}

			for(local.i in arguments.selectStatement.getWhereCriteria()) {
				if(getFieldSQLType(local.i.field) CONTAINS "char") {
					local.formattedClause = local.i.statement.replaceNoCase(local.i.field, local.i.field & " IS NOT NULL AND LOWER(" & local.i.field & ")");
					whereSQL = replaceNoCase(whereSQL, local.i.statement, "(" & local.formattedClause & ")", "one");
				}
			}
		}

		if(orderBySQL.len() > 0) {
			for(local.i in arguments.selectStatement.getOrderCriteria()) {
				local.field = listFirst(local.i, " ").trim();
				// QoQ cant do calculated values inside ORDER BY - only as part of the SELECT
				if(fieldExists(local.field) && getFieldSQLType(local.field) CONTAINS "char") {
					if(!findNoCase("_order_" & local.field, selectSQL)) {
						selectSQL = listAppend(selectSQL, "LOWER(" & local.field & ") _order_" & local.field);
						if(len(groupBySQL) > 0) {
							groupBySQL = listAppend(groupBySQL, "_order_" & local.field);
						}
					}

					local.formattedClause = "_order_" & local.field & " " & listLast(local.i, " ");
					orderBySQL = replace(orderBySQL, local.i, local.formattedClause);
				}
			}
		}

		var result = queryExecute(
			trim(selectSQL & " FROM query " & whereSQL & " " & groupBySQL & " " & orderBySQL),
			parameters,
			{ dbtype: "query" }
		);

		// strip _order_ columns from the query
		if(findNoCase("_order_", result.columnList)) {
			result = queryExecute(
				"SELECT #arguments.selectStatement.getSelect()# FROM result",
				[],
				{ dbtype: "query" }
			);
		}

		// at this point, we know our working record count
		var totalRecordCount = result.recordCount;

		// result pagination, if necessary (this uses the underlying (undocumented) removeRows method so we don't need to run additional QoQ - IT IS ZERO-BASED)
		if(arguments.offset > totalRecordCount) {
			result.removeRows(0, totalRecordCount);
		} else if(arguments.offset == 1 && arguments.limit > 0) {
			result.removeRows(arguments.limit, totalRecordCount - arguments.limit);
		} else if(arguments.offset > 1) {
			if(arguments.limit <= 0) {
				throw(type = "InvalidLimit", message = "Limit must be furnished when offset is defined");
			}

			// set limit to the record count of the query if we're past the limit
			arguments.limit = (arguments.limit > totalRecordCount) ? totalRecordCount : arguments.limit;

			// dealing w/ zero-based
			limitIndex = arguments.offset - 1;

			var startIndex = arguments.offset + arguments.limit;

			// remove from the end of the query first
			if(startIndex < totalRecordCount) {
				result.removeRows(startIndex, totalRecordCount - startIndex);
			}

			result.removeRows(0, arguments.offset);
		}

		result
			.getMetadata()
				.setExtendedMetadata({
					cached: true,
					recordCount: result.recordCount,
					totalRecordCount: totalRecordCount
				});

		return result;
	}

	boolean function fieldExists(required string fieldName) {
		return listFindNoCase(variables.query.columnList, arguments.fieldName);
	}

	boolean function fieldIsFilterable(required string fieldName) {
		return fieldExists(arguments.fieldName);
	}

	string function getFieldList() {
		return arrayToList(variables.query.getMetadata().getColumnLabels());
	}

	string function getFieldSQL(required string fieldName) {
		return "";
	}

	string function getFieldSQLType(required string fieldName) {
		return variables.query.getMetadata().getColumnTypeName(variables.query.findColumn(javaCast("string", arguments.fieldName)));
	}

	// buyer beware! this is passed by reference. changes to the query object may have unintended consequences
	query function getQuery() {
		return variables.query;
	}

	QueryOfQueries function makeWritable() {
		if(!structKeyExists(variables, "identifierField")) {
			throw(type = "MissingIdentifierField", message = "No identifierField has been defined");
		}

		// set internal columns to facilitate modification
		if(!listFindNoCase(variables.query.columnList, "_modifiedDateUTC")) {
			local.dateValues = [];
			arraySet(local.dateValues, 1, variables.query.recordCount, now());
			queryAddColumn(variables.query, "_modifiedDateUTC", "timestamp", local.dateValues);
		}

		return this;
	}

	lib.sql.InsertStatement function insert(required struct fields) {
		return new InsertStatement(this, arguments.fields);
	}

	lib.sql.SelectStatement function select(string fieldList = "*") {
		return new SelectStatement(this).select(arguments.fieldList);
	}

	lib.sql.UpdateStatement function update(required struct fields) {
		return new UpdateStatement(this, arguments.fields);
	}

	lib.sql.UpsertStatement function upsert(required struct fields) {
		return new UpsertStatement(this, arguments.fields);
	}

}