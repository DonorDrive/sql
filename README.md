# sql
A fluent interface for SQL interactions in ColdFusion

##Motivation
As DonorDrive has grown, our need to pull data from disparate sources has grown. Creating a common set of interfaces to tackle integrations with these data sources facilitates downstream development and maintenance.

##Getting Started
The `sql` project assumes that it will reside in a `lib` directory under the web root, or mapped in the consuming application.

###How does it work?
`IQueryable` implementations must furnish a `select()` method. The implementation instantiates `lib.sql.SelectStatement` along with a reference to itself. The other methods of `IQueryable` allow `SelectStatment` to inspect the `Queryable` for properties necessary to parse and subsequently return control to the `IQueryable` implementation when the `execute()` method is invoked. Pagination and limiting are supported during `execute()` by furnishing `offset` and `limit` arguments.

`IWritable` implementations extend `IQueryable` to fill out the whole CRUD acronym. `insert()`, `update()`, `upsert()`, and `delete()` are all supported by the interface.

An implementation that supports all operations is included in this package: `QueryOfQueries`. To use, simply instantiate with an existing CF-query:

```
myQuery = queryNew(
	"id, createdDate, foo, bar",
	"varchar, timestamp, integer, bit",
	[
		{ id: createUUID(), createdDate: now(), foo: 1, bar: true },
		{ id: createUUID(), createdDate: now(), foo: 2, bar: false },
		{ id: createUUID(), createdDate: now(), foo: 3, bar: true },
		{ id: createUUID(), createdDate: now(), foo: 4, bar: true },
		{ id: createUUID(), createdDate: now(), foo: 5, bar: false }
	]
);

myQoQ = new lib.sql.QueryOfQueries(myQuery);

writeDump(myQoQ.select().where("foo >= 4").orderBy("foo DESC").execute());
```