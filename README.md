# Serverless election with AWS

This is a demo of how a national election could be done with a multi-region active-active serverless setup on AWS.

The AWS services used include Lambda, API Gateway, Route 53, DynamoDB, S3, Cloudfront, Cloudwatch, KMS, and SQS. The Terraform templates and code used is at [github.com/tylerpearson/election-on-aws](https://github.com/tylerpearson/election-on-aws).

A JSON API endpoint with real-time results is located at [api.election.tylerpearson.cloud/votes](https://api.election.tylerpearson.cloud/votes).

A blog post on how it all works is coming soon.

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

## Architecture

![Diagram](diagram.png?raw=true "Architecture")
