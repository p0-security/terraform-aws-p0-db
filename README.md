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
GRANT rds_superuser TO p0_iam_manager WITH ADMIN OPTION;
```

## Module usage

### Cluster (Aurora) example

```hcl
module "p0_db" {
  source = "github.com/p0-security/terraform-aws-p0-db"

  rds_cluster_arn             = aws_rds_cluster.example.arn
  lambda_execution_role_name  = aws_iam_role.p0_connector.name
  connector_security_group_id = aws_security_group.p0_connector.id
}
```

### Instance example

```hcl
module "p0_db" {
  source = "github.com/p0-security/terraform-aws-p0-db"

  rds_instance_arn            = aws_db_instance.example.arn
  lambda_execution_role_name  = aws_iam_role.p0_connector.name
  connector_security_group_id = aws_security_group.p0_connector.id
}
```

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `rds_cluster_arn` | ARN of the RDS cluster. Set exactly one of `rds_cluster_arn` or `rds_instance_arn`. | `string` | `null` | One of `rds_cluster_arn` or `rds_instance_arn` |
| `rds_instance_arn` | ARN of the RDS DB instance. Set exactly one of `rds_cluster_arn` or `rds_instance_arn`. | `string` | `null` | One of `rds_cluster_arn` or `rds_instance_arn` |
| `lambda_execution_role_name` | Name of the connector Lambda function's service role. | `string` | — | Yes |
| `connector_security_group_id` | ID of the P0 connector Lambda's security group. | `string` | — | Yes |

### Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9.0 |
| aws | ~> 5.0 |
