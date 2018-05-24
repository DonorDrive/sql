component accessors = "true" extends = "FilterStatement" {

	property name = "orderBy" type = "string" setter = "false" default = "";
	property name = "orderBySQL" type = "string" setter = "false" default = "";
	property name = "orderCriteria" type = "array" setter = "false";
	property name = "select" type = "string";
	property name = "selectSQL" type = "string" setter = "false" default = "*";

	SelectStatement function init(required IQueryable queryable) {
		// init internals that don't have defaults
		structAppend(variables, {
				orderCriteria: [],
				select: arguments.queryable.getFieldList()
			});

		return super.init(arguments.queryable);
	}

	query function execute(numeric limit = -1, numeric offset = 1) {
		return getQueryable().executeSelect(this, arguments.limit, arguments.offset);
	}

	SelectStatement function orderBy(string orderBy = "") {
		variables.orderBy = arguments.orderBy;
		variables.orderBySQL = "";
		variables.orderCriteria = [];

		if(variables.orderBy.listLen() > 0) {
			for(local.i = 1; local.i <= variables.orderBy.listLen(); local.i++) {
				local.orderItem = trim(variables.orderBy.listGetAt(local.i));

				if(local.orderItem.listLen(" ") == 1) {
					local.orderItem = local.orderItem & " ASC";
				} else if(local.orderItem.listLen(" ") > 2) {
					throw(type = "ParseOrderError", message = "The statement '#local.orderItem#' could not be parsed");
				}

				local.field = local.orderItem.listFirst(" ").trim();
				local.direction = local.orderItem.listLast(" ");

				if(!getQueryable().fieldExists(local.field)) {
					throw(type = "UndefinedOrderByField", message = "The field '#local.field#' does not exist in this view");
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
		// assume that by calling select, the user is starting from the top
		variables.activeFieldList = "";
		variables.select = arguments.select;
		variables.selectSQL = "";

		if(variables.select == "*") {
			variables.select = getQueryable().getFieldList();
		}

		for(local.field in variables.select) {
			local.field = local.field.trim();

			if(!getQueryable().fieldExists(local.field)) {
				throw(type = "UndefinedSelectField", message = "The field '#local.field#' does not exist");
			}

			// update our SELECT + fieldList
			variables.activeFieldList = variables.activeFieldList.listAppend(local.field);
			variables.selectSQL = variables.selectSQL.listAppend(getQueryable().getFieldSQL(local.field).len() > 0 ? getQueryable().getFieldSQL(local.field) & " " & local.field : local.field);
		}

		variables.activeFieldList = variables.activeFieldList.listRemoveDuplicates();

		variables.selectSQL = "SELECT " & variables.selectSQL;

		return this;
	}

}