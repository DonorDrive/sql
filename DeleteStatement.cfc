component accessors = "true" extends = "FilterStatement" {

	DeleteStatement function init(required IWritable writable) {
		return super.init(arguments.writable);
	}

	void function execute() {
		getQueryable().executeDelete(this);
	}

}