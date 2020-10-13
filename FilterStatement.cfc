component accessors = "true" {

	property name = "activeFieldList" type = "string";
	property name = "parameters" type = "array" setter = "false";
	property name = "queryable" type = "IQueryable" setter = "false";
	property name = "whereCriteria" type = "array" setter = "false";
	property name = "whereForEvaluation" type = "string" setter = "false";
	property name = "whereSQL" type = "string" setter = "false" default = "";

	FilterStatement function init(required IQueryable queryable) {
		// init internals that don't have defaults
		structAppend(
			variables,
			{
				"activeFieldList": "",
				"fieldList": arguments.queryable.getFieldList(),
				"parameters": [],
				"queryable": arguments.queryable,
				"where": "",
				"whereCriteria": [],
				"whereForEvaluation": ""
			}
		);

		return this;
	}

	string function getWhere() {
		return variables.where;
	}

	FilterStatement function where(string where = "") {
		variables.parameters = [];
		variables.where = arguments.where;
		variables.whereSQL = arguments.where;
		variables.whereCriteria = [];

		if(arguments.where.len() > 0) {
			variables.whereForEvaluation = arguments.where;
			/*
				sub expressions:
				1: the target column
				2: the operator
				3: the value...
					the contents between two parenthesis (IN/NOT IN)
					OR a single-quoted value containing 0 or more of an escaped ' (\') or anything not a '
					OR a string of non-whitespace, non-) characters
			*/
			local.pattern = "(\w+)\s*(!=|>=|>|<=|<|=|IN|NOT\s+IN|LIKE)\s*(\([^\)]+\)|'(\\'|[^'])*'|[^\s|)]+)";
			local.matches = REFindNoCase(local.pattern, arguments.where, 1, true);

			while(local.matches.pos[1] > 0) {
				local.statement = mid(arguments.where, local.matches.pos[1], local.matches.len[1]);
				local.field = mid(arguments.where, local.matches.pos[2], local.matches.len[2]);
				local.operator = uCase(REReplace(mid(arguments.where, local.matches.pos[3], local.matches.len[3]), "\s+", " ", "all"));

				if(local.operator == "IN" || local.operator == "NOT IN") {
					// for IN, we need to remove the parenthesis, before parsing the value list
					local.value = trim(REReplace(mid(arguments.where, local.matches.pos[4], local.matches.len[4]), "^\(|\)$", "", "all"));
					local.values = REMatch("'(\\'|[^'])*'|\w+", local.value);

					for(local.i = 1; local.i <= local.values.len(); local.i++) {
						// replace the value with a placeholding element to verify parse
						local.value = replace(local.value, local.values[local.i], local.i);
						local.values[local.i] = local.values[local.i].REReplace("^[']|[']$", "", "all");
						local.values[local.i] = replace(local.values[local.i], "\'", "'", "all");
					}

					if(local.values.len() != listLen(local.value)) {
						throw(type = "lib.sql.InvalidWhereCriteriaException", message = "The filter clause (#local.statement#) provided could not be parsed");
					}
				} else {
					local.value = REReplace(mid(arguments.where, local.matches.pos[4], local.matches.len[4]), "^[']|[']$", "", "all");
					local.value = replace(local.value, "\'", "'", "all");
					local.values = [ local.value ];
				}

				if(getQueryable().fieldExists(local.field) && getQueryable().fieldIsFilterable(local.field)) {
					// preserve the case dictated within the IQueryable
					local.field = listGetAt(variables.fieldList, listFindNoCase(variables.fieldList, local.field));

					for(local.value in local.values) {
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
									throw(type = "lib.sql.InvalidWhereCriteriaException", message = "The '#local.value#' is not a valid value for '#local.field#'");
								}
								break;
							case "bit":
								if(!isBoolean(local.value)) {
									throw(type = "lib.sql.InvalidWhereCriteriaException", message = "The '#local.value#' is not a valid value for '#local.field#'");
								}
								break;
							case "date":
							case "time":
							case "timestamp":
								if(!isDate(local.value)) {
									throw(type = "lib.sql.InvalidWhereCriteriaException", message = "The '#local.value#' is not a valid value for '#local.field#'");
								}
								break;
							default:
								if(!isSimpleValue(local.value)) {
									throw(type = "lib.sql.InvalidWhereCriteriaException", message = "The '#local.value#' is not a valid value for '#local.field#'");
								}
								break;
						};
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
							// https://unix.stackexchange.com/questions/128019/why-is-the-unit-separator-ascii-31-invisible-in-terminal-output
							"separator": chr(31),
							"value": arrayToList(local.values, chr(31))
						}
					);
				} else {
					throw(type = "lib.sql.UndefinedWhereFieldException", message = "The field '#local.field#' does not exist, or is not filterable");
				}

				variables.activeFieldList = variables.activeFieldList.listAppend(local.field);

				// replace this particular statement in the whereForEvaluation, so we can validate the whole thing before sending to DB
				variables.whereForEvaluation = replace(variables.whereForEvaluation, local.statement, arrayLen(variables.parameters));
				local.matches = REFindNoCase(local.pattern, arguments.where, (local.matches.pos[1] + local.matches.len[1]), true);
			}

			// verify our WHERE isn't gonna bust anything...
			if(variables.whereForEvaluation.uCase().REFind("[^\d|AND|OR|\(|\)|\s]") > 0) {
				throw(type = "lib.sql.InvalidWhereCriteriaException", message = "The filter criteria (#variables.whereForEvaluation#) provided could not be parsed");
			}

			try {
				evaluate(variables.whereForEvaluation);
			} catch(Any e) {
				throw(type = "lib.sql.InvalidWhereStatementException", message = "The 'where' statement could not be parsed");
			}

			variables.activeFieldList = variables.activeFieldList.listRemoveDuplicates();

			variables.whereSQL = "WHERE (" & variables.whereSQL & ")";
		}

		return this;
	}

}