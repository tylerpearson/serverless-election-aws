# Serverless election with AWS

This is a demo of how a national election could be done with a multi-region active-active serverless setup on AWS.

The AWS services used include Lambda, API Gateway, Route 53, DynamoDB, S3, Cloudfront, Cloudwatch, KMS, and SQS. The Terraform templates and code used is at [github.com/tylerpearson/election-on-aws](https://github.com/tylerpearson/election-on-aws).

A JSON API endpoint with real-time results is located at [api.election.tylerpearson.cloud/votes](https://api.election.tylerpearson.cloud/votes).

A blog post on how it all works is coming soon.

## Architecture

![Diagram](diagram.png?raw=true "Architecture")
