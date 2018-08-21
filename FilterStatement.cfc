component accessors = "true" {

	property name = "activeFieldList" type = "string";
	property name = "parameters" type = "array" setter = "false";
	property name = "queryable" type = "IQueryable" setter = "false";
	property name = "where" type = "string" setter = "false" default = "";
	property name = "whereCriteria" type = "array" setter = "false";
	property name = "whereSQL" type = "string" setter = "false" default = "";

	FilterStatement function init(required IQueryable queryable) {
		// init internals that don't have defaults
		structAppend(
			variables,
			{
				"activeFieldList": arguments.queryable.getFieldList(),
				"parameters": [],
				"queryable": arguments.queryable,
				"where": "",
				"whereCriteria": []
			}
		);

		return this;
	}

	FilterStatement function where(string where = "") {
		variables.parameters = [];
		variables.where = arguments.where;
		variables.whereSQL = arguments.where;

		if(arguments.where.len() > 0) {
			local.whereEval = arguments.where;
			local.pattern = "(\w+)\s*(!=|>=|>|<=|<|=|IN|NOT\s+IN|LIKE)\s*(\([^\)]+\)|'[^']*'|""[^""]*""|[^\s|)]+)";
			local.matches = REFindNoCase(local.pattern, arguments.where, 1, true);

			while(local.matches.pos[1] > 0) {
				local.statement = mid(arguments.where, local.matches.pos[1], local.matches.len[1]);
				local.field = mid(arguments.where, local.matches.pos[2], local.matches.len[2]);
				local.operator = uCase(REReplace(mid(arguments.where, local.matches.pos[3], local.matches.len[3]), "\s+", " ", "all"));

				if(local.operator == "IN" || local.operator == "NOT IN") {
					// for IN, we need to remove the closing parenthesis, before parsing the value list
					local.value = trim(REReplace(mid(arguments.where, local.matches.pos[4], local.matches.len[4]), "^\(|\)$", "", "all"));
					local.values = REMatch("'[^']*'|""[^""]*""|\w+", local.value);

					// a difference in the parsed values versus the list length means something aint right
					if(local.values.len() != listLen(local.value)) {
						throw(type = "InvalidWhereCriteria", message = "The filter clause (#local.statement#) provided could not be parsed");
					}

					for(local.i = 1; local.i <= local.values.len(); local.i++) {
						local.values[local.i] = local.values[local.i].REReplace("^['|""]|['|""]$", "", "all");
					}

					local.value = arrayToList(local.values);
				} else {
					local.value = REReplace(mid(arguments.where, local.matches.pos[4], local.matches.len[4]), "^['|""]|['|""]$", "", "all");
				}

				if(getQueryable().fieldExists(local.field) && getQueryable().fieldIsFilterable(local.field)) {
					switch(getQueryable().getFieldSQLType(local.field)) {
						case "bigint":
						case "decimal":
						case "double":
						case "money":
						case "numeric":
						case "float":
						case "real":
						case "integer":
						case "smallint":
						case "tinyint":
							if(!isNumeric(local.value)) {
								throw(type = "InvalidWhereCriteria", message = "The '#local.value#' is not a valid value for '#local.field#'");
							}
							break;
						case "bit":
							if(!isBoolean(local.value)) {
								throw(type = "InvalidWhereCriteria", message = "The '#local.value#' is not a valid value for '#local.field#'");
							}
							break;
						case "date":
						case "time":
						case "timestamp":
							if(!isDate(local.value)) {
								throw(type = "InvalidWhereCriteria", message = "The '#local.value#' is not a valid value for '#local.field#'");
							}
							break;
						default:
							if(!isSimpleValue(local.value)) {
								throw(type = "InvalidWhereCriteria", message = "The '#local.value#' is not a valid value for '#local.field#'");
							}
							break;
					}

					// replace the Queryable field w/ underlying SQL equivalent, in the case of IN, wrap the param in parenthesis
					local.parsedStatement = ((getQueryable().getFieldSQL(local.field).len() > 0 ? getQueryable().getFieldSQL(local.field) : local.field) & " " & local.operator & ((local.operator == "IN" || local.operator == "NOT IN") ? " (?)" : " ?"));

					variables.whereSQL = replace(
						variables.whereSQL,
						local.statement,
						local.parsedStatement
					);

					arrayAppend(
						variables.whereCriteria,
						{
							"field": local.field,
							"operator": local.operator,
							"statement": local.parsedStatement
						}
					);

					arrayAppend(
						variables.parameters,
						{
							"cfsqltype": getQueryable().getFieldSQLType(local.field),
							"list": (local.operator == "IN" || local.operator == "NOT IN"),
							"value": local.value
						}
					);
				} else {
					throw(type = "UndefinedWhereField", message = "The field '#local.field#' does not exist, or is not filterable");
				}

				variables.activeFieldList = variables.activeFieldList.listAppend(local.field);

				// replace this particular statement in the whereEval, so we can validate the whole thing before sending to DB
				local.whereEval = replace(local.whereEval, local.statement, arrayLen(variables.parameters));
				local.matches = REFindNoCase(local.pattern, arguments.where, (local.matches.pos[1] + local.matches.len[1]), true);
			}

			// verify our WHERE isn't gonna bust anything...
			if(local.whereEval.uCase().REFind("[^\d|AND|OR|\(|\)|\s]") > 0) {
				throw(type = "InvalidWhereCriteria", message = "The filter criteria (#local.whereEval#) provided could not be parsed");
			}

			try {
				evaluate(local.whereEval);
			} catch(Any e) {
				throw(type = "InvalidWhereCriteria", message = "The 'where' statement could not be parsed");
			}

			variables.activeFieldList = variables.activeFieldList.listRemoveDuplicates();

			variables.whereSQL = "WHERE (" & variables.whereSQL & ")";
		}

		return this;
	}

}