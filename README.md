# Serverless election on AWS

## Description

This is a demo of how a national election could be done with a multi-region active-active serverless setup on AWS. It follows the *scalable webhook pattern* [as described here](https://www.jeremydaly.com/serverless-microservice-patterns-for-aws/), where a SQS queue sits between two Lambda functions to act as a buffer for any bursts in requests or protect against any write throttling on DynamoDB tables. This ensures every vote is successfully saved.

Currently, it uses `us-east-1` and `us-west-1`, but the Terraform templates can be easily adjusted to use more regions, if desired. [Latency-based routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html#routing-policy-latency) is used in Route 53 to guide incoming requests to the user's closest AWS region.

After the request comes into the region, [API Gateway](https://aws.amazon.com/api-gateway/) triggers a Lambda function that places the vote into an SQS queue. Downstream, a second Lambda function polls the SQS queue and saves the vote to the DynamoDB tables. These Lambda functions use the recently announced [support for Ruby](https://aws.amazon.com/blogs/compute/announcing-ruby-support-for-aws-lambda/).

There are two DynamoDB tables. The first is `voters`, which contains information on all registered voters, including their voter id and state. It contains information on each voter (e.g. name, address, and state). The partition key is the `voter_id` attribute, which is a unique id generated for each voter that they use to cast their votes. The `voters` table is also the *source of truth* for all votes -- when a vote is saved, the voter's item in the table is updated with the candidate they voted for and the time they voted. A `global secondary index` also exists on this table called `state-candidate-index`. This projects the state and candidate attributes so results can be queried without requiring a scan on a table that contains hundreds of millions of items when all registered voters in the United States are loaded into the `voters` table.

Additionally, there is a second DynamoDB table called `results` that contains a summary of the number of votes each candidate received in each state and can be easily queried to get information on the results by state and candidate. A third Lambda function called `results` is hooked up to the API Gateway to expose a JSON response of the current results so they could theoretically be be viewed in real time (for example, if a state official wanted to view the number of votes cast at different points during Election Day).

The DynamoDB tables exist in each region and use [Global Tables](https://aws.amazon.com/dynamodb/global-tables/) to keep data in sync between regions. Auto-scaling is enabled to better handle fluctuations of reads and writes to each table.

Logs are sent to Cloudwatch and can act as an audit trail of the votes that have been cast.

The primary AWS services used in this setup are Lambda, API Gateway, Route 53, DynamoDB, S3, Cloudfront, Cloudwatch, KMS, and SQS.

The Terraform templates and code used is at [github.com/tylerpearson/election-on-aws](https://github.com/tylerpearson/election-on-aws).

## Election Day simulation

The `scripts` directory contains

## Blog post

A more in-depth writeup on how it all works is coming soon.

## Website

A static website hosted on S3 with a simple example UI of how voters interact with the API is located at https://election.tylerpearson.cloud.

A JSON API endpoint with real-time results is located at https://api.election.tylerpearson.cloud/votes.

## Architecture diagram

![Diagram](diagram.png?raw=true "Architecture")

## Directory structure

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
1. Change variables in `terraform.tfvars` to what you matches your setup.
1. Run `terraform plan` and ensure the output matches what you expect.
1. Run `terraform apply` to build the infrastructure.
1. The website will be located at the output of `website_url`. The API is available at the output of `api_url`. To access the region-specific APIs, use the outputs of `invocation_url`.

## Disclaimers

- This demo doesn't take into account whether online/electronic voting *should* be done, just how it *could* be done with current AWS services. The web [is](https://www.chicagotribune.com/suburbs/highland-park/news/ct-hpn-election-integrity-forum-tl-1102-20171031-story.html) [full](https://engineering.stanford.edu/magazine/article/david-dill-why-online-voting-danger-democracy) [of](https://www.vox.com/policy-and-politics/2018/8/13/17683666/florida-voting-system-hack-children) [opinions](https://www.politico.com/story/2018/10/13/west-virginia-voting-app-security-846130), if you're looking for that.
- While encryption at rest is enabled on all the services that support it, there currently isn't any sort of client-side encryption setup.
- In something as critical as a Presidential election, it would likely make sense to use all four regions that currently exist in the United States. Tweak `main.tf` to add additional regions.
- The code currently doesn't support write-in votes and assumes that four presidential candidates are on the ballot in every state, which isn't the case.
- While the results are broken down by state, this demo assumes shifting the management of the election to some sort of central federal agency that manages voting across the country instead of the individual states' responsibility.

