# terraform-aws-p0-db
Install AWS infrastructure for a P0 database integration on RDS

## Database configuration

👉 Prior to running the Terraform in this module, you must also configure your database. 👈

You can accomplish this either by running commands manually in the database, or by using a third-party Terraform provider for your database.

Here only the database SQL commands are given.

_MySQL_

Configure P0's access in a AWS RDS MySQL database by running:

```
CREATE USER p0_iam_manager IDENTIFIED WITH AwsAuthenticationPlugin AS 'RDS';
GRANT CREATE USER, CREATE ROLE ON *.* TO p0_iam_manager;
GRANT ROLE_ADMIN ON *.* TO p0_iam_manager;
GRANT ALL PRIVILEGES ON `%`.* TO p0_iam_manager WITH GRANT OPTION;
```

_PostgreSQL_

Configure P0's access in a AWS RDS Postgres database by running:

```
CREATE USER p0_iam_manager;
GRANT rds_iam TO p0_iam_manager;
ALTER USER p0_iam_manager WITH CREATEROLE;
GRANT ALL PRIVILEGES ON *.* TO p0_iam_manager WITH GRANT OPTION;
```
