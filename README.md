# Demo of the U.S. National Presidential Election on AWS with Serverless

- [Overview](#overview)
- [Instructions](#instructions)
- [Architecture](#architecture)
- [Directory structure](#directory-structure)
- [Implementation](#implementation)
  - [DynamoDB](#dynamodb)
  - [API Gateway](#api-gateway)
  - [Lambda](#lambda)
  - [SQS](#sqs)
  - [CloudFront and S3](#cloudfront-and-s3)
  - [CloudWatch Metrics and Logs](#cloudwatch-metrics-and-logs)
  - [KMS](#kms)
  - [IAM](#iam)
  - [Certificate Manager](#certificate-manager)
- [Election simulation](#election-simulation)
- [Website](#website)
- [Disclaimers](#disclaimers)

## Overview

This is a demo of how a national election could be done with a multi-region active-active serverless setup on AWS. It follows the *scalable webhook pattern* [as described here](https://www.jeremydaly.com/serverless-microservice-patterns-for-aws/), where a SQS queue sits between two Lambda functions to act as a buffer for any bursts in requests or protect against any write throttling on DynamoDB tables. This ensures every vote is successfully saved.

Currently, it uses `us-east-1` and `us-west-1`, but the Terraform templates can be easily adjusted to use more regions, if desired. [Latency-based routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html#routing-policy-latency) is used in Route 53 to guide incoming requests to the voters's closest AWS region. Route 53 health checks are in place to detect issues with the API and redirect traffic to another region, if neccessary.

After the request comes into the region, [API Gateway](https://aws.amazon.com/api-gateway/) triggers a Lambda function that places the vote into an SQS queue. Downstream, a second Lambda function polls the SQS queue and saves the vote to the DynamoDB tables. These Lambda functions use the recently announced [support for Ruby](https://aws.amazon.com/blogs/compute/announcing-ruby-support-for-aws-lambda/).

There are two DynamoDB tables. The first is `voters`, which contains information on all registered voters, including their voter id and state. It contains information on each voter (e.g. name, address, and state). The partition key is the `voter_id` attribute, which is a unique id generated for each voter that they use to cast their votes. The `voters` table is also the *source of truth* for all votes -- when a vote is saved, the voter's item in the table is updated with the candidate they voted for and the time they voted. A `global secondary index` also exists on this table called `state-candidate-index`. This projects the state and candidate attributes so results can be queried without requiring a scan on a table that contains hundreds of millions of items when all registered voters in the United States are loaded into the `voters` table.

Additionally, there is a second DynamoDB table called `results` that contains a summary of the number of votes each candidate received in each state and can be easily queried to get information on the results by state and candidate. A third Lambda function called `results` is hooked up to the API Gateway to expose a JSON response of the current results so they could theoretically be be viewed in real time (for example, if a state official wanted to view the number of votes cast at different points during Election Day).

The DynamoDB tables exist in each region and use [Global Tables](https://aws.amazon.com/dynamodb/global-tables/) to keep data in sync between regions. Auto-scaling is enabled to better handle fluctuations of reads and writes to each table.

Logs are sent to CloudWatch and can act as an audit trail of the votes that have been cast.

The primary AWS services used in this setup are Lambda, API Gateway, Route 53, DynamoDB, S3, CloudFront, CloudWatch, KMS, and SQS.

The Terraform templates and code used is at [github.com/tylerpearson/serverless-election-aws](https://github.com/tylerpearson/serverless-election-aws).

## Instructions

To use these Terraform templates:

1. Make sure Terraform is installed and up-to-date by running `terraform --version`. [Visit here for instructions](https://learn.hashicorp.com/terraform/getting-started/install.html) on how to install Terraform.
1. Change the config in `state.tf` to match the bucket, region, and profile you will be using to interact with the templates.
1. Change variables in `terraform.tfvars` to what matches your setup.
1. Run `terraform init` to initialize the required dependencies.
1. Run `terraform plan` and double check that the output matches what you expect.
1. Run `terraform apply` to build the infrastructure.
1. The website will be located at the output of `website_url`. The API is available at the output of `api_url`. To access the region-specific APIs, use the outputs of `invocation_url`.

To destroy everything created above, run `terraform destroy`. Note that there are costs associated with these resources if they are left on.

## Architecture

Two regions are used (us-east-1 and us-west-1).

![Diagram](diagram.png?raw=true "Architecture")

## Directory structure

```
.
├── modules
│   ├── api
│   ├── database
│   ├── encrpytion
│   ├── functions
│   ├── queue
│   └── region
├── scripts
└── website
```

- `modules` - Terraform modules for each component
  - `api` - API Gateway, region-specific DNS setup, and IAM roles and permissions required for interacting with Lambda
  - `database` - Setup for DynamoDB tables. Autoscaling policies
  - `encryption` - KMS resources used by other resources for encryption at rest of data
  - `functions` - Lambda functions for creating and saving votes.
  - `queue` - SQS queues as the stage between the API request and saving the vote to DynamoDB
  - `region` a module containing setup for the above modules. Reusable across regions
- `scripts` - Scripts for loading mock voters into the tables and doing load testing of voting
- `website` - Static website in S3 with an example UI of how voters interact with the API.

## Implementation

### DynamoDB

- DynamoDB is used to store information on voters and votes cast during the election.
- There are two tables used, `Voters` and `Results`. There is more detailed info on how each table is used below.
- The tables exist in the two active AWS regions, `us-east-1` and `us-west-2`. Each table is setup as a global table to enable multi-region multi-master writes and reads.
- Auto-scaling is enabled on the tables and indexes to keep provisioned writes and reads at optimal levels.
- DynamoDB's support for [encryption at rest](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/EncryptionAtRest.html) is used on each table for an additional level of protection when the data is stored.
- [Point-in-time recovery](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/PointInTimeRecovery.html) is enabled as an additional protection against unexpected data corruption issues.

### Voters table

The Voters table contain an item for each registered voter. Attributes included are the standard address, name, and state. Additionally, every voter has a globally unique `id` that they use to cast their vote. As votes are cast, the `candidate` and `voted_at` attributes are added to keep track of the candidate the voter selected and at what time the vote was cast.

```
Voters {
  id: string (uuid, primary partition key)
  address: string
  first_name: string
  last_name: string
  state: string
  candidate: string
  voted_at: string
}
```

There is one global secondary index on the Voters table to make it easier to search for results by state and candidate. This index contains is sparse until votes are cast because it relies on the `candidate` attribute. Only three attributes are projected: `state`, `candidate`, and `id` because this index would primarily be used for `COUNT` type queries (e.g. how many votes in Michigan were cast for Hillary Clinton). Limiting the attributes that are projected helps with query time and reduces the required provisioned write and read throughput.

```
StateCandidateIndex {
  state: string (partition key)
  candidate: string (sort key)
  id: string
}
```

### Results table

The `Results` table is a summary table that keeps track of the number of votes cast for each candidate in each state. As votes are cast, the count is incremenented on the item for the candidate in the voter's state. This makes it easier to see the number of votes cast on Election Day and during early voting. The `Voters` table should be relied on as the source of truth for votes cast and the `Results` table should be used as an estimate due to the [risks involved with atomic counters](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/WorkingWithItems.html#WorkingWithItems.AtomicCounters).

```
Results {
  state: string (partition key)
  candidate: string (sort key)
  count: integer
}
```

### Route 53

To be added.

### API Gateway

- Currently, the API Gateway does not use a WAF. Since voting infrastructure would absolutely be a target for attacks like DDOS, a WAF would make sense to be used for rate limiting and to protect against other common attacks.

### Lambda

- There are four Lambda functions. Three are triggered by the API Gateway and one is triggered by messages in the SQS queue.
- The default max number of concurrent invocations is 1,000. This would want to be bumped up before votes are cast to protect against rate limiting. It is critical for the `vote_enqueuer` function to operate properly every time to ensure that the vote is properly registered, so it would likely make sense to allocate reserved executions. Since messages are passed to the SQS queue, the downstream `vote_processor` functions can back up some without a negative impact (similar to how there is some time between polls closing on Election Day and the results being counted).
- The functions take advantage of the [new support for the Ruby language](https://aws.amazon.com/blogs/compute/announcing-ruby-support-for-aws-lambda/).
- Logs are output to CloudWatch and encrypted.

#### Vote enqueuer function

When a vote is cast from the voting UI website, JavaScript triggers a POST HTTP request to the API Gateway. The API Gateway then routes the request to the `vote_enqueuer` function. This function can respond in three different ways:

1. If the id of the voter does not exist in the DynamoDB table (for example, a voter mistypes it), the Lambda responds with a message and response code to the front-end letting the voter know it does not exist.
1. If the voter id does exist, but the voter has already cast a vote, a message and response code is returned to let the voter know they cannot vote multiple times.
1. If the voter id does exist, and the voter cast not already cast a vote, it places a JSON message in the SQS queue with the voter id and candidate they selected.

#### Vote processor function

When a message containing the vote information is sent to the SQS queue, a downstream Lambda function called `vote_processor` consumes the message. This function will update the voter's item in the `Voters` DynamoDB table to include the time the vote was cast and who the candidate voted for. Additionally, this function increments the candidate's count in the `Results` table.

If an exception occurs, for example if the DynamoDB tables are under-provisioned and a write or read fails, the message will be placed back on the SQS queue and [retried twice](https://docs.aws.amazon.com/lambda/latest/dg/retries-on-errors.html). If the function continues to fail, [the message is sent to a Dead Letter Queue](https://docs.aws.amazon.com/lambda/latest/dg/dlq.html) and can be reviewed to make sure that all votes cast are properly registered.

#### Health check function

The health check function is a simple Lambda function that responds to health checks triggered by Route 53. This checks that API Gateway and Lambda are working properly in the region. It could be modified to do additional checks against DynamoDB and SQS.

#### Results function

The `results` function is triggered by an API request and shares the current totals from the `Results` DynamoDB table. There is currently no caching, so every API request triggers a lookup on the table.

### SQS

- SQS acts as a queue between a Lambda function triggered by the API Gateway and a Lambda function triggered by messages in the SQS queue. This takes advantages of [Lambda's recent integration support for SQS -> Lambda](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html).
- The queue uses server-side encryption with the KMS CMK. This protects against a burst of messages that could overwhelm writes to the DynamoDB table before autoscaling kicks in.
- Vote updates on the DynamoDB table are idempotent, so the standard queue is used and FIFO isn't required.
- The message retention period is bumped up to the max of 14 days, although due to the Lambda integration, the messages will be processed in near real-time.
- Visibility timeout is set at the default 30 seconds, which is adequate for the time required for Lambda to update the record in DynamoDB.
- If the queue is changed to FIFO, [SQS deduping](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/using-messagededuplicationid-property.html) should be done on the messages to prevent multiple votes being cast if there is a delay between a vote being cast and a vote being saved to the database. The voter id should be used as the deduplication id.
- CloudWatch alerts should be setup to notify if the queues start to back up.

### CloudFront and S3

To be added.

### CloudWatch Metrics and Logs

- CloudWatch is used to track metrics and logs across the AWS services used.
- Where possible (for instance in the logs generated by Lambda), [the logs are encrypted using the KMS customer master key](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html) for an additional layer of protection.
- All incoming votes processed are written to the logs, which provides an additional audit trail.
- Currently, the CloudWatch logs aren't set to archive to S3 and have no additional protection against deletion, which would be a must for any election to protect against vote tampering or any sort of manipulation. A pattern that could be used is `CloudWatch Logs -> Firehose -> S3` with the destination being a secondary AWS account. This secondary account would have all the bells and whistles enabled (e.g. MFA deletion protection, CloudTrail, highly restrictive IAM policies) to ensure the integrity of the vote.
- [Detailed CloudWatch Metrics](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-metrics-and-dimensions.html) are turned on for the API Gateway deployments to provide better visibility into how they are working.

```hcl
resource "aws_cloudwatch_log_group" "vote_enqueuer_lambda_log_group" {
  name       = "/aws/lambda/${aws_lambda_function.vote_enqueuer_lambda.function_name}"
  kms_key_id = "${var.kms_arn}"
}
```

### KMS

To be added.

### IAM

To be added.

### Certificate Manager

- AWS Certificate Manager is used to provision TLS/SSL certificates to protect data in transit on the static website and API endpoints.
- A certificate is requested *in each region* for the API endpoints. While the certificates are being issued for the to protect the same domain and subdomains, this **is required in each region** because [ACM's certs are region-specific](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-regional-api-custom-domain-create.html). Once the certificates are issued, they can be assigned to the custom domains setup for each region's API Gateways.
- [CloudFront distributions require using certificates issued in the us-east-1 region](https://docs.aws.amazon.com/acm/latest/userguide/acm-regions.html). Because of this requirement, the voting UI static website that is hosted on S3 with CloudFront uses the certificate issued in the `us-east-1` region.
- [DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-validate-dns.html) is used for domain authentication.
- Certificates are only requested for the domains/subdomains that are used to [slightly reduce the risk that wildcard certs can introduce](https://www.cloudconformity.com/conformity-rules/ACM/wildcard-domain-name.html).

## Election simulation

The `scripts` directory contains a few Ruby scripts that can be used to load the DynamoDB tables with sample voters and voter file data. Additionally, there are scripts that are used to simulate voting that would occur on Election Day.

```
.
├── Gemfile
├── Gemfile.lock
├── data/
├── generate_registered_voters.rb
├── generate_votes.rb
├── load_registered_voters.rb
└── populate_results_table.rb
```

- `Gemfile` - Script dependencies. Run `bundle install` before using the scripts to ensure the libraries are installed and ready to use.
- `data` - A directory used to store data that the scripts will generate and consume.
- `generate_registered_voters.rb` - Generates 1,366,692 sample voters with unique voter ids. This is 1% of the number of votes cast in the 2016 Presidential Election. Outputs to the `data` directory.
- `load_registered_voters.rb` - Loads the sample voters generated in the above script into a DynamoDB table.
- `populate_results_table.rb` - Populates the `results` table with base data on each state and candidate. As the votes are cast and the Lambda functions run, the counts are incremented.
- `generate_votes.rb` - Simulates votes being cast for the 1,366,692 voters generated above. The votes cast in the simulation match the actual split of votes cast for each candidate in each state (but at 1% of what was actually cast).

## Website

A static website hosted on S3 with a simple example UI of how voters interact with the API is located at https://election.tylerpearson.cloud.

A JSON API endpoint with real-time results is located at https://api.election.tylerpearson.cloud/votes.

## Disclaimers

- This demo doesn't take into account whether online/electronic voting *should* be done, just how it *could* be done with current AWS services. The web [is](https://www.chicagotribune.com/suburbs/highland-park/news/ct-hpn-election-integrity-forum-tl-1102-20171031-story.html) [full](https://engineering.stanford.edu/magazine/article/david-dill-why-online-voting-danger-democracy) [of](https://www.vox.com/policy-and-politics/2018/8/13/17683666/florida-voting-system-hack-children) [opinions](https://www.politico.com/story/2018/10/13/west-virginia-voting-app-security-846130), if you're looking for that.
- While encryption at rest is enabled on all the services that support it, there currently isn't any sort of client-side encryption setup. SSL certificates are in place to help protect data in transit.
- In something as critical as a Presidential election, it would likely make sense to use all four regions that currently exist in the United States. Tweak `main.tf` to add additional regions.
- The code currently doesn't support write-in votes and assumes that five presidential candidates (Trump, Clinton, Johnson, Stein, McMullin) are on the ballot in every state, which isn't the case.
- While the results are broken down by state, this demo assumes shifting the management of the election to some sort of central federal agency that manages voting across the country instead of the individual states' responsibility.
- There's a ton of additional functionality and services that could be setup and used (CloudWatch alarms for notifications of issues, GuardDuty and CloudTrail for security, X-Ray for better visibility in the Lambda functions, etc.) that isn't included. I timeboxed many parts of this demo in the sake of time.

