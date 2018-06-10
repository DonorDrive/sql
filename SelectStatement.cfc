component accessors = "true" extends = "FilterStatement" {

	property name = "aggregates" type = "array" setter = "false";
	property name = "groupBy" type = "string" setter = "false" default = "";
	property name = "groupBySQL" type = "string" setter = "false" default = "";
	property name = "orderBy" type = "string" setter = "false" default = "";
	property name = "orderBySQL" type = "string" setter = "false" default = "";
	property name = "orderCriteria" type = "array" setter = "false";
	property name = "select" type = "string";
	property name = "selectSQL" type = "string" setter = "false" default = "*";

	SelectStatement function init(required IQueryable queryable) {
		// init internals that don't have defaults
		structAppend(
			variables,
			{
				"aggregates": [],
				"orderCriteria": [],
				"select": arguments.queryable.getFieldList()
			}
		);

		return super.init(arguments.queryable);
	}

	query function execute(numeric limit = -1, numeric offset = 1) {
		if(arrayLen(variables.aggregates) > 0 && len(variables.groupBy) == 0) {
			local.groupBy = variables.activeFieldList;

			// exclude all aggregates - in order to group on everything else
			for(local.aggregate in variables.aggregates) {
				local.groupBy = listDeleteAt(local.groupBy, listFind(local.groupBy, local.aggregate.field));
			}

			if(len(local.groupBy) > 0) {
				this.groupBy(local.groupBy);
			}
		}

		return getQueryable().executeSelect(this, arguments.limit, arguments.offset);
	}

	SelectStatement function groupBy(string groupBy = "") {
		variables.groupBy = arguments.groupBy;
		variables.groupBySQL = "";

		if(variables.groupBy.listLen() > 0) {
			for(local.i = 1; local.i <= variables.groupBy.listLen(); local.i++) {
				local.field = trim(variables.groupBy.listGetAt(local.i));

				if(!getQueryable().fieldExists(local.field)) {
					throw(type = "UndefinedGroupByField", message = "The field '#local.field#' does not exist in this IQueryable");
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
			for(local.i = 1; local.i <= variables.orderBy.listLen(); local.i++) {
				local.orderField = trim(variables.orderBy.listGetAt(local.i));

				if(local.orderField.listLen(" ") == 1) {
					local.orderField = local.orderField & " ASC";
				} else if(local.orderField.listLen(" ") > 2) {
					throw(type = "ParseOrderError", message = "The statement '#local.orderField#' could not be parsed");
				}

				local.field = local.orderField.listFirst(" ").trim();
				local.direction = local.orderField.listLast(" ");

				if(!getQueryable().fieldExists(local.field)) {
					throw(type = "UndefinedOrderByField", message = "The field '#local.field#' does not exist in this IQueryable");
				} else if(local.direction != "ASC" && local.direction != "DESC") {
					throw(type = "ParseOrderError", message = "The direction '#local.direction#' is not supported");
				} else {
					// append to our list of active fields
					variables.activeFieldList = variables.activeFieldList.listAppend(local.field);
					// update order criteria and our SQL
					arrayAppend(variables.orderCriteria, local.field & " " & local.direction);
					variables.orderBySQL = listAppend(variables.orderBySQL, (getQueryable().getFieldSQL(local.field).len() > 0 ? getQueryable().getFieldSQL(local.field) : local.field) & " " & local.direction);
				}
			}

			// remove any dupes in our list
			variables.activeFieldList = variables.activeFieldList.listRemoveDuplicates();

			variables.orderBySQL = "ORDER BY " & variables.orderBySQL;
		}

		return this;
	}

	SelectStatement function select(string select = "*") {
		// start with the casing dictated upstream
		local.fieldList = getQueryable().getFieldList();

		// assume that by calling select, the user is starting from the top
		variables.activeFieldList = "";
		variables.select = arguments.select;
		variables.selectSQL = "";

		if(variables.select == "*") {
			variables.select = getQueryable().getFieldList();
		}

		for(local.field in variables.select) {
			local.field = local.field.trim();

			if(getQueryable().fieldExists(local.field)) {
				// preserve the case dictated within the IQueryable
				local.field = listGetAt(local.fieldList, listFindNoCase(local.fieldList, local.field));

				variables.selectSQL = variables.selectSQL.listAppend(getQueryable().getFieldSQL(local.field).len() > 0 ? getQueryable().getFieldSQL(local.field) & " " & local.field : local.field);
			} else {
				// check if it's a calculated column
				local.aggregateCheck = REFindNoCase("^(AVG|COUNT|MAX|MIN|SUM)\s*\((\w+)\)$", local.field, 1, true);

				if(arrayLen(local.aggregateCheck.len) == 3) {
					local.operation = uCase(mid(local.field, local.aggregateCheck.pos[2], local.aggregateCheck.len[2]));
					local.field = mid(local.field, local.aggregateCheck.pos[3], local.aggregateCheck.len[3]);

					if(getQueryable().fieldExists(local.field) && arrayFindNoCase([ "bigint", "date", "decimal", "double", "float", "integer", "money", "numeric", "real", "smallint", "time", "timestamp", "tinyint" ], getQueryable().getFieldSQLType(local.field))) {
						local.aggregate = {};
						// preserve the case dictated within the IQueryable
						local.aggregate.field = listGetAt(local.fieldList, listFindNoCase(local.fieldList, local.field));
						local.aggregate.alias = lCase(local.operation) & uCase(mid(local.aggregate.field, 1, 1)) & mid(local.aggregate.field, 2, len(local.aggregate.field));
						local.aggregate.operation = local.operation;

						arrayAppend(variables.aggregates, local.aggregate);

						variables.selectSQL = variables.selectSQL.listAppend(local.aggregate.operation & "(" & local.aggregate.field & ") " & local.aggregate.alias);
					} else {
						throw(type = "InvalidAggregateField", message = "The field '#local.field#' is not viable for aggregation");
					}
				} else {
					throw(type = "UndefinedSelectField", message = "The field '#local.field#' does not exist");
				}
			}

			variables.activeFieldList = variables.activeFieldList.listAppend(local.field);
		}

		variables.activeFieldList = variables.activeFieldList.listRemoveDuplicates();

		variables.selectSQL = "SELECT " & variables.selectSQL;

		return this;
	}

}