data "snowflake_schemas" "database_schemas" {
  in {
    database = var.database_name
  }
  with_describe   = false
  with_parameters = false
}
