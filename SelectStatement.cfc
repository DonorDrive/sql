component accessors = "true" extends = "FilterStatement" {

	property name = "aggregates" type = "array" setter = "false";
	property name = "groupByString" type = "string" setter = "false" default = "";
	property name = "groupBySQL" type = "string" setter = "false" default = "";
	property name = "orderBySQL" type = "string" setter = "false" default = "";
	property name = "orderCriteria" type = "array" setter = "false";
	property name = "selectSQL" type = "string" setter = "false" default = "*";

	SelectStatement function init(required IQueryable queryable) {
		// init internals that don't have defaults
		structAppend(
			variables,
			{
				"aggregates": [],
				"orderCriteria": [],
				"orderBy": "",
				"select": arguments.queryable.getFieldList()
			}
		);

		return super.init(arguments.queryable);
	}

	query function execute(numeric limit = -1, numeric offset = 0) {
		if(arrayLen(variables.aggregates) > 0) {
			if(len(variables.groupBy) == 0) {
				local.groupBy = variables.select;

				// exclude all aggregates - in order to group on everything else
				for(local.aggregate in variables.aggregates) {
					local.groupBy = listDeleteAt(local.groupBy, listFindNoCase(local.groupBy, local.aggregate.alias));
				}

				if(len(local.groupBy) > 0) {
					this.groupBy(local.groupBy);
				}
			}

			// replace the alias with the actual calculated columns
			for(local.aggregate in variables.aggregates) {
				variables.selectSQL = variables.selectSQL.replaceNoCase(local.aggregate.alias, (local.aggregate.operation & "(" & local.aggregate.field & ") " & local.aggregate.alias));
			}
		}

		arguments.selectStatement = this;

		return getQueryable().executeSelect(argumentCollection = arguments);
	}

	string function getOrderBy() {
		return variables.orderBy;
	}

	string function getSelect() {
		return variables.select;
	}

	SelectStatement function groupBy(string groupBy = "") {
		variables.groupBy = arguments.groupBy;
		variables.groupBySQL = "";

		if(variables.groupBy.listLen() > 0) {
			for(local.groupBy in variables.groupBy) {
				local.field = trim(local.groupBy);

				if(!getQueryable().fieldExists(local.field)) {
					throw(type = "lib.sql.UndefinedGroupByFieldException", message = "The field '#local.field#' does not exist in this IQueryable");
				} else {
					// append to our list of active fields
					variables.activeFieldList = variables.activeFieldList.listAppend(local.field);
					variables.groupBySQL = listAppend(variables.groupBySQL, local.field);
				}
			}

			// remove any dupes in our list
			variables.activeFieldList = variables.activeFieldList.listRemoveDuplicates();
		}

		variables.groupBySQL = "GROUP BY " & variables.groupBySQL;

		return this;
	}

	SelectStatement function orderBy(string orderBy = "") {
		variables.orderBy = arguments.orderBy;
		variables.orderBySQL = "";
		variables.orderCriteria = [];

		if(variables.orderBy.listLen() > 0) {
			for(local.orderBy in variables.orderBy) {
				local.orderField = trim(local.orderBy);

				if(local.orderField.listLen(" ") == 1) {
					local.orderField = local.orderField & " ASC";
				} else if(local.orderField.listLen(" ") > 2) {
					throw(type = "lib.sql.ParseOrderErrorException", message = "The statement '#local.orderField#' could not be parsed");
				}

				local.field = local.orderField.listFirst(" ").trim();
				local.direction = local.orderField.listLast(" ");

				if((!getQueryable().fieldExists(local.field) || !getQueryable().fieldIsFilterable(local.field))
						&& !listFindNoCase(variables.select, local.field)
					) {
					throw(type = "lib.sql.UndefinedOrderByFieldException", message = "The field '#local.field#' does not exist, or is not filterable");
				} else if(local.direction != "ASC" && local.direction != "DESC") {
					throw(type = "lib.sql.ParseOrderErrorException", message = "The direction '#local.direction#' is not supported");
				} else {
					if(getQueryable().fieldExists(local.field)) {
						// preserve the case dictated within the IQueryable
						local.field = listGetAt(variables.fieldList, listFindNoCase(variables.fieldList, local.field));

						variables.orderBySQL = listAppend(variables.orderBySQL, (getQueryable().getFieldSQL(local.field).len() > 0 ? getQueryable().getFieldSQL(local.field) : local.field) & " " & local.direction);
					} else {
						local.field = listGetAt(variables.select, listFindNoCase(variables.select, local.field));

						// a calculated field present in the select list
						variables.orderBySQL = listAppend(variables.orderBySQL, local.field & " " & local.direction);
					}

					// append to our list of active fields
					variables.activeFieldList = variables.activeFieldList.listAppend(local.field);
					// update order criteria and our SQL
					arrayAppend(variables.orderCriteria, local.field & " " & local.direction);
				}
			}

			// remove any dupes in our list
			variables.activeFieldList = variables.activeFieldList.listRemoveDuplicates();

			variables.orderBySQL = "ORDER BY " & variables.orderBySQL;
		}

		return this;
	}

	SelectStatement function select(string select = "*") {
		// assume that by calling select, the user is starting from the top
		variables.activeFieldList = "";
		variables.select = arguments.select;
		variables.selectSQL = "";

		if(variables.select == "*") {
			variables.select = variables.fieldList;
		}

		variables.select = variables.select.REReplace("\s+", "", "all");

		for(local.field in variables.select) {
			if(getQueryable().fieldExists(local.field)) {
				// preserve the case dictated within the IQueryable
				local.field = listGetAt(variables.fieldList, listFindNoCase(variables.fieldList, local.field));

				variables.selectSQL = variables.selectSQL.listAppend(getQueryable().getFieldSQL(local.field).len() > 0 ? getQueryable().getFieldSQL(local.field) & " " & local.field : local.field);
			} else {
				// check if it's a calculated column
				local.aggregateCheck = REFindNoCase("^(AVG|COUNT|MAX|MIN|SUM)\s*\((\w+)\)$", local.field, 1, true);

				if(arrayLen(local.aggregateCheck.len) == 3) {
					local.rawField = local.field;
					local.operation = uCase(mid(local.field, local.aggregateCheck.pos[2], local.aggregateCheck.len[2]));
					local.field = mid(local.field, local.aggregateCheck.pos[3], local.aggregateCheck.len[3]);

					if(getQueryable().fieldExists(local.field)) {
						if(local.operation == "COUNT" || arrayFindNoCase([ "bigint", "date", "datetime", "decimal", "double", "float", "integer", "money", "numeric", "real", "smallint", "time", "timestamp", "tinyint" ], getQueryable().getFieldSQLType(local.field))) {
							local.aggregate = {};
							// preserve the case dictated within the IQueryable
							local.aggregate.field = listGetAt(variables.fieldList, listFindNoCase(variables.fieldList, local.field));
							local.aggregate.alias = lCase(local.operation) & uCase(mid(local.aggregate.field, 1, 1)) & mid(local.aggregate.field, 2, len(local.aggregate.field));
							local.aggregate.operation = local.operation;

							arrayAppend(variables.aggregates, local.aggregate);

							// replace the computed value w/ the alias for now
							variables.select = replaceNoCase(variables.select, local.rawField, local.aggregate.alias);

							// the actual SQL will be dropped in just before exection
							local.field = local.aggregate.alias;

							variables.selectSQL = variables.selectSQL.listAppend(local.field);
						} else {
							throw(type = "lib.sql.InvalidAggregateFieldException", message = "The field '#local.field#' is not viable for aggregation");
						}
					} else {
						throw(type = "lib.sql.UndefinedSelectFieldException", message = "The field '#local.field#' does not exist");
					}
				} else {
					throw(type = "lib.sql.UndefinedSelectFieldException", message = "The field '#local.field#' does not exist");
				}
			}

			variables.activeFieldList = variables.activeFieldList.listAppend(local.field);
		}

		variables.activeFieldList = variables.activeFieldList.listRemoveDuplicates();

		variables.selectSQL = "SELECT " & variables.selectSQL;

		return this;
	}

}