# Serverless election with AWS

This is a demo of how a national election could be done with a multi-region active-active serverless setup on AWS.

The AWS services used include Lambda, API Gateway, Route 53, DynamoDB, S3, Cloudfront, Cloudwatch, KMS, and SQS. The Terraform templates and code used is at [github.com/tylerpearson/election-on-aws](https://github.com/tylerpearson/election-on-aws).

A JSON API endpoint with real-time results is located at [api.election.tylerpearson.cloud/votes](https://api.election.tylerpearson.cloud/votes).

A blog post on how it all works is coming soon.

## Architecture

![Diagram](diagram.png?raw=true "Architecture")

## Structure

```
.
├── modules
│   ├── api
│   ├── database
│   ├── functions
│   ├── queue
│   └── region
├── scripts
└── website
```

- `modules` - Terraform modules for each component
  - `api` - API Gateway, region-specific DNS setup, and IAM roles and permissions required for interacting with Lambda
  - `database` - Setup for DynamoDB tables. Autoscaling policies
  - `functions` - Lambda functions for creating and saving votes.
  - `queue` - SQS queues as the stage between the API request and saving the vote to DynamoDB
  - `region` a module containing setup for the above modules. Reusable across regions
- `scripts` - Scripts for loading mock voters into the tables and doing load testing of voting
- `website` - Static website in S3 with an example UI of how voters interact with the API.

## Terraform

To use these Terraform templates:

1. Change the config in `state.tf` to match the bucket, region, and profile you will be using to interact with the templates.
1. Change variables in `variables.tf` to the domain configuration you plan on using.
1. Run `terraform plan --var-file=variables.tfvars` and ensure the output matches what you expect.
1. Run `terraform apply --var-file=variables.tfvars` to build the infrastructure.
1. The website will be located at the output of `website_url`. The API is available at the output of `api_url`. To access the region-specific APIs, use the outputs of `invocation_url`.
