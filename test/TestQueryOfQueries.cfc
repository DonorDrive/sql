component extends = "mxunit.framework.TestCase" {

	function setup() {
		variables.query = queryNew(
			"id, createdDate, foo, bar",
			"varchar, timestamp, integer, bit"
		);

		for(local.i = 1; local.i <= 1000; local.i++) {
			queryAddRow(
				variables.query,
				{
					"id": createUUID(),
					"createdDate": now(),
					"foo": local.i,
					"bar": ( local.i % 2 )
				}
			);
		}

		variables.qoq = new lib.sql.QueryOfQueries(query = variables.query).setIdentifierField("id");
	}

	function test_delete() {
		variables.qoq.delete().where("bar = 1").execute();
		local.result = variables.qoq.select().execute();
		assertEquals(500, local.result.getMetadata().getExtendedMetadata().recordCount);
		assertEquals(500, local.result.getMetadata().getExtendedMetadata().totalRecordCount);
	}

	function test_fieldExists() {
		assertTrue(variables.qoq.fieldExists("foo"));
		assertFalse(variables.qoq.fieldExists("foob"));
	}

	function test_getFieldList() {
		assertEquals("id,createdDate,foo,bar", variables.qoq.getFieldList());
	}

	function test_getFieldSQL() {
		assertEquals("", variables.qoq.getFieldSQL("id"));
	}

	function test_getFieldSQLType() {
		assertEquals("varchar", variables.qoq.getFieldSQLType("id"));
		assertEquals("timestamp", variables.qoq.getFieldSQLType("createdDate"));
		assertEquals("integer", variables.qoq.getFieldSQLType("foo"));
		assertEquals("bit", variables.qoq.getFieldSQLType("bar"));
	}

	function test_getIdentifierField() {
		assertEquals("id", variables.qoq.getIdentifierField());
	}

	function test_insert() {
		variables.qoq.insert({ "id": createUUID(), "createdDate": now(), "foo": "1001", "bar": false }).execute();
		local.result = variables.qoq.select().execute();
		assertEquals(1001, local.result.getMetadata().getExtendedMetadata().recordCount);
		assertEquals(1001, local.result.getMetadata().getExtendedMetadata().totalRecordCount);
	}

	function test_select() {
		local.result = variables.qoq.select("*").execute();
		assertTrue(local.result.getMetadata().getExtendedMetadata().cached);
		assertEquals(1000, local.result.getMetadata().getExtendedMetadata().recordCount);
		assertEquals(1000, local.result.getMetadata().getExtendedMetadata().totalRecordCount);
	}

	function test_select_orderBy() {
		local.result = variables.qoq.select("foo").orderBy("foo DESC").execute(limit = 10);
		assertEquals("1000,999,998,997,996,995,994,993,992,991", valueList(local.result.foo));
		assertEquals(10, local.result.getMetadata().getExtendedMetadata().recordCount);
		assertEquals(1000, local.result.getMetadata().getExtendedMetadata().totalRecordCount);
	}

	function test_select_where() {
		local.result = variables.qoq.select("foo").where("foo > 500").execute();
		assertEquals(500, local.result.getMetadata().getExtendedMetadata().recordCount);
		assertEquals(500, local.result.getMetadata().getExtendedMetadata().totalRecordCount);
	}

	function test_select_where_DDMAINT_12971() {
		try {
			local.result = variables.qoq.select().where("'1' = '1' AND foo = 1").execute();
		} catch(Any e) {
			local.threwTheException = true;
			assertEquals("InvalidWhereCriteria", e.type);
		}

		assertTrue(structKeyExists(local, "threwTheException"));
	}

	function test_select_where_DD_6709() {
		local.result = variables.qoq.select().where("id = '#lCase(variables.query.id[1])#'").execute();
		debug(local.result);
		debug(local.result.getMetadata().getExtendedMetadata());
		assertEquals(1, local.result.recordCount);
	}

	function test_select_where_DDMAINT_13527() {
		local.result = variables.qoq.select().where("id IN ('#variables.query.id[1]#', '#variables.query.id[2]#')").execute();
		debug(local.result);
		debug(local.result.getMetadata().getExtendedMetadata());
		assertEquals(2, local.result.recordCount);
	}

	function test_select_where_orderBy() {
		local.result = variables.qoq.select("foo").where("foo > 500").orderBy("foo DESC").execute(limit = 10, offset = 11);
		assertEquals("990,989,988,987,986,985,984,983,982,981", valueList(local.result.foo));
		assertEquals(10, local.result.getMetadata().getExtendedMetadata().recordCount);
		assertEquals(500, local.result.getMetadata().getExtendedMetadata().totalRecordCount);
	}

	function test_select_where_orderBy_DD_11399() {
		local.result = variables.qoq.select("id").where("id IN ('#variables.query.id[1]#', '#variables.query.id[2]#')").orderBy("id DESC").execute(limit = 10);
		debug(local.result.getMetadata());
//		assertEquals(10, local.result.getMetadata().getExtendedMetadata().recordCount);
//		assertEquals(1000, local.result.getMetadata().getExtendedMetadata().totalRecordCount);
	}

	function test_update() {
		variables.qoq.update({ "foo": "1", "bar": false }).where("foo <= 500").execute();
		local.result = variables.qoq.select().where("foo = 1").execute();
		assertEquals(500, local.result.getMetadata().getExtendedMetadata().recordCount);
	}

	function test_upsert() {
		variables.qoq.upsert({ "foo": "1", "bar": false }).where("foo <= 500").execute();
		local.result = variables.qoq.select().where("foo = 1").execute();
		assertEquals(500, local.result.getMetadata().getExtendedMetadata().recordCount);
	}

	function test_upsert_new() {
		variables.qoq.upsert({ "id": createUUID(), "createdDate": now(), "foo": "3000", "bar": false }).where("foo = 3000").execute();
		local.result = variables.qoq.select().where("foo = 3000").execute();
		assertEquals(1, local.result.getMetadata().getExtendedMetadata().recordCount);
	}

}