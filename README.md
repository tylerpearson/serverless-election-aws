# Demo Serverless Architecture of the U.S. Presidential Election on AWS

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
  - [X-Ray](#x-ray)
- [Election simulation](#election-simulation)
- [Website](#website)
- [Disclaimers](#disclaimers)

## Overview

This is a demo of how a national election could be done with a multi-region active-active serverless setup on AWS. It follows the *scalable webhook pattern* [as described here](https://www.jeremydaly.com/serverless-microservice-patterns-for-aws/), where a SQS queue sits between two Lambda functions to act as a buffer for any bursts in requests or protect against any write throttling on DynamoDB tables. This ensures every vote is successfully saved.

Currently, it uses `us-east-1` and `us-west-1`, but the Terraform templates can be easily adjusted to use more regions, if desired. [Latency-based routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html#routing-policy-latency) is used in Route 53 to guide incoming requests to the voter's closest AWS region. Route 53 health checks are in place to detect issues with the API and redirect traffic to another region, if necessary.

After the request comes into the region, [API Gateway](https://aws.amazon.com/api-gateway/) triggers a Lambda function that places the vote into an SQS queue. Downstream, a second Lambda function polls the SQS queue and saves the vote to the DynamoDB tables. These Lambda functions use the recently announced [support for Ruby](https://aws.amazon.com/blogs/compute/announcing-ruby-support-for-aws-lambda/).

There are two DynamoDB tables. The first is `Voters`, which contains information on all registered voters, including their voter id and state. It contains information on each voter (e.g. name, address, and state). The partition key is the `id` attribute, which is a unique id generated for each voter that they use to cast their votes. The `Voters` table is also the *source of truth* for all votes -- when a vote is saved, the voter's item in the table is updated with the candidate they voted for and the time they voted. A global secondary index also exists on this table called `StateCandidateIndex`. This projects the state and candidate attributes so results can be queried without requiring a scan on a table that contains hundreds of millions of items when all registered voters in the United States are loaded into the `Voters` table.

Additionally, there is a second DynamoDB table called `Results` that contains a summary of the number of votes each candidate received in each state and can be easily queried to get information on the results by state and candidate. A third Lambda function called `Results` is hooked up to the API Gateway to expose a JSON response of the current results so they could theoretically be be viewed in real time (for example, if a state official wanted to view the number of votes cast during early voting or at different points during Election Day).

The DynamoDB tables exist in each region and use [Global Tables](https://aws.amazon.com/dynamodb/global-tables/) to keep data in sync between regions. Auto-scaling is enabled to better handle fluctuations of reads and writes to each table.

Logs are sent to CloudWatch and can act as an audit trail of the votes that have been cast.

The primary AWS services used in this setup are Lambda, API Gateway, Route 53, DynamoDB, S3, CloudFront, CloudWatch, KMS, SQS, and X-Ray.

The Terraform templates and code used is at [github.com/tylerpearson/serverless-election-aws](https://github.com/tylerpearson/serverless-election-aws).

---

### Example voting flow

1. Citizens register to vote using the normal process.
1. Registered voters are loaded into the central database and a unique id is generated for each person.
1. Before voting begins, registered voters are delivered through the mail a letter with the unique id to the address where they are registered.
1. Instead of travelling to a polling location for voting, voters log in to the Voting website and cast their vote using the unique id that arrived in the mail.

---

### Why Serverless?

- It's highly scalable and automatically adjusts based on usage. During the peak of Election Day, there would likely be thousands of votes cast per second. A properly designed Serverless setup would be able to handle this without blinking an eye.
- It's cost efficient. With it's usage-based pricing, costs are tied very closely to the number of registered voters and votes cast.
- It shifts operational responsibilities to AWS. AWS has some of the best teams in the world working on areas like security and operations, so by running on top of AWS, customers benefit from economies at scale.

### Why multi-region?

- An election is as high stakes as it gets, so reliability, resiliency, and redundancy are paramount. You can't redo an election. Running in multiple regions allow for near instant failover in a scenario where issues arise in a region.
- AWS has four regions in the United States: `us-east-1` in Virginia, `us-east-2` in Ohio, `us-west-1` in California and `us-west-2` in Oregon that are completely isolated from each region. While these regions are open to the general public, there are two GovCloud regions in `us-east` and `us-west` that are available for government use. In the very hypothetical scenario of a presidential election running on AWS, it would be assumed that the GovCloud regions would be used due to the incredibly strict requirements that would be involved.

---

**Please note that this demo doesn't take into account whether online/electronic voting *should* be done, just how it *could* be done with current AWS services. There are a lot of compelling arguments on why electronic voting should not be done.**

---

## Instructions

To use these Terraform templates:

1. Make sure Terraform is installed and up-to-date by running `terraform --version`. [Visit here for instructions](https://learn.hashicorp.com/terraform/getting-started/install.html) on how to install Terraform.
1. Change the config in `state.tf` to match the bucket, region, and profile you will be using to interact with the templates.
1. Change variables in `terraform.tfvars` to what matches your setup.
1. Run `terraform init` to initialize the required dependencies.
1. Run `terraform plan` and double check that the output matches what you expect.
1. Run `terraform apply` to build the infrastructure.
1. The website will be located at the output of `website_url`. The API is available at the output of `api_url`. To access the region-specific APIs, use the outputs of `invocation_url`.

To destroy everything created above, run `terraform destroy`. Note that there are costs associated with some of these resources if they are left on.

## Architecture

Two AWS regions are used (`us-east-1` and `us-west-1`).

![Diagram](assets/diagram.png?raw=true "Architecture")

## Directory structure

```
.
├── modules
│   ├── api
│   ├── database
│   ├── encryption
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
- The tables exist in the two active AWS regions, `us-east-1` and `us-west-1`. Each table is setup as a global table to enable multi-region multi-master writes and reads.
- Auto-scaling is enabled on the tables and indexes to keep provisioned writes and reads at optimal levels.
- DynamoDB's support for [encryption at rest](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/EncryptionAtRest.html) is used on each table for an additional level of protection when the data is stored.
- [Point-in-time recovery](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/PointInTimeRecovery.html) is enabled as an additional protection against unexpected data corruption issues.

### Voters table

The Voters table contain an item for each registered voter. Attributes included are the standard address, name, and state. Additionally, every voter has a globally unique `id` that they use to cast their vote. As votes are cast, the `candidate` and `voted_at` attributes are added to keep track of the candidate the voter selected and at what time the vote was cast.

```js
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

```js
StateCandidateIndex {
  state: string (partition key)
  candidate: string (sort key)
  id: string
}
```

### Results table

The `Results` table is a summary table that keeps track of the number of votes cast for each candidate in each state. As votes are cast, the count is incremented on the item for the candidate in the voter's state. This makes it easier to see the number of votes cast on Election Day and during early voting. The `Voters` table should be relied on as the source of truth for votes cast and the `Results` table should be used as an estimate due to the [risks involved with atomic counters](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/WorkingWithItems.html#WorkingWithItems.AtomicCounters).

```js
Results {
  state: string (partition key)
  candidate: string (sort key)
  count: integer
}
```

### Route 53

- Route 53 is used for domain registration and DNS. I registered a domain outside of the Terraform templates and used it for this demo. To use these templates, change the `domain_name` variable in the `terraform.tfvars` file to a domain that is present in your AWS account.
- A separate [public hosted zone](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/CreatingHostedZone.html) is created at the `election` subdomain and contains all the records required for this project.
- Route 53 is used for DNS validation of certificates issued through AWS Certificate Manager.
- To route voters to their closest AWS region, [latency based routing is enabled](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html) to point at the API Gateway endpoints.
- An ALIAS DNS record for each region is created. Each record is assigned to a custom health check to verify that the region is healthy. This health check hits the API Gateway endpoint, which triggers the health check Lambda function. If a region is detected as unhealthy, traffic is automatically redirected away from the unhealthy region to provide high availability. When the region is detected as healthy again, traffic will automatically be enabled again.
- Each health check measures latency, so any API degradations can be alerted upon.

### API Gateway

- API Gateway is used to route HTTP requests to the Lambda functions. Each API Gateway is regional (vs edge) and exists solely in the region it was deployed in. By using latency based routing with Route 53, requests are directed to the voter's closest region. This allows redundancy and automatic failover.
- There are three primary endpoints:
  - `GET /health` - Used by the Route 53 health checks to verify a region's health.
  - `GET /votes` - Triggers the `results` Lambda function and returns a JSON response of the current election results by state and candidate.
  - `POST /votes` - Receives a JSON payload with the vote that is cast by the the voter. This payload looks like `{ id: "163uc-3NQXD-Wgfgg", candidate: "Hillary Clinton" }`. Additionally a `OPTIONS` endpoint exists to [enable CORS requests](https://serverless.com/blog/cors-api-gateway-survival-guide/) sent by JavaScript in the Voting UI website. The location of the website is whitelisted as a permitted origin.
- CloudWatch Logs and CloudWatch Metrics are enabled for better visibility into requests and performance.
- One stage exists: `production`. Additional ones could easily be created for testing.
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

When a message containing the vote information is sent to the SQS queue, a downstream Lambda function called `vote_processor` consumes the message. This function will update the voter's item in the `Voters` DynamoDB table to include the time the vote was cast and who the candidate voted for. Additionally, this function increments the candidate's count in the `Results` table. Since the `Results` table is only used for estimates, there isn't a need to use the newly announced [DynamoDB transactions](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transactions.html) to guarantee the writes to both tables succeed.

If an exception occurs, for example if the DynamoDB tables are under-provisioned and a write or read fails, the message will be placed back on the SQS queue and [retried twice](https://docs.aws.amazon.com/lambda/latest/dg/retries-on-errors.html). If the function continues to fail, [the message is sent to a Dead Letter Queue](https://docs.aws.amazon.com/lambda/latest/dg/dlq.html) and can be reviewed to make sure that all votes cast are properly registered.

#### Health check function

The health check function is a simple Lambda function that responds to health checks triggered by Route 53. This checks that API Gateway and Lambda are working properly in the region. It could be modified to do additional checks against DynamoDB and SQS so that every critical part of the stack is checked.

#### Results function

The `results` function is triggered by an API request and shares the current totals from the `Results` DynamoDB table. There is currently no caching, so every API request triggers a lookup on the table.

### SQS

- SQS acts as a queue between a Lambda function triggered by the API Gateway and a Lambda function triggered by messages in the SQS queue. This takes advantages of [Lambda's recent integration support for SQS -> Lambda](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html). More information on how [Lambda scales with SQS is available here](https://docs.aws.amazon.com/en_us/lambda/latest/dg/scaling.html).
- The queue protects against a burst of messages that could overwhelm writes to the DynamoDB table before autoscaling kicks in.
- KMS adds a layer of encryption to the messages.
- Vote updates on the DynamoDB table are idempotent, so messages can be safely run more than once with no impact.
- If the Lambda function is not able to process the message successfully after two attempts, the message is passed to the dead letter queue and would be manually reviewed.
- The message retention period is set at three days, although due to the Lambda integration, the messages will be processed in near real-time. For the dead letter queue, the retention period is the maximum seven days.
- Visibility timeout is set at the default 30 seconds, which is adequate for the time required for Lambda to update the record in DynamoDB.


### CloudFront and S3

- An S3 bucket is used to host the the voting UI. The bucket has [static website hosting](https://docs.aws.amazon.com/AmazonS3/latest/dev/WebsiteHosting.html) enabled to serve the HTML, CSS, JS, and other required resources.
- In front of the static website bucket is a CloudFront distribution to serve the resources to voters through a CDN.
- Terraform does not yet support the ability to [designate an origin failover](https://github.com/terraform-providers/terraform-provider-aws/issues/6547). For the high availability required to support an election, this would want to be enabled in case [any issues with S3](https://aws.amazon.com/message/41926/) arise.
- Due to the global nature of CloudFront distributions, a TLS/SSL certificate is [required from the default `us-east-1` region](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html#https-requirements-aws-region). In the Terraform templates, the distribution is assigned the certificate generated in this region.
- The distribution forces HTTPS for secure communication.

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

- KMS is used to encrypt data to help protect against improper access.
- A customer managed CMKs is created and assigned to resources that support using it for encryption, for example SQS and CloudWatch Logs.
- Key rotation is enabled to [reduce risk](https://www.cloudconformity.com/conformity-rules/KMS/key-rotation-enabled.html).
- [DynamoDB does not support use of customer managed CMKs](https://docs.aws.amazon.com/kms/latest/developerguide/services-dynamodb.html), so instead the AWS managed customer master key is enabled to protect data at rest. [DynamoDB will keep the key in memory](https://docs.aws.amazon.com/kms/latest/developerguide/services-dynamodb.html) for up to twelve hours to reduce the number of required API calls to decrypt data.
- [KMS access is logged to CloudTrail](https://docs.aws.amazon.com/kms/latest/developerguide/logging-using-cloudtrail.html) so that an audit trail exists.

### IAM

- IAM policies are applied to resources and follow the [principle of least privilege](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#grant-least-privilege) to avoid improper access.

### Certificate Manager

- AWS Certificate Manager is used to provision TLS/SSL certificates to protect data in transit on the static website and API endpoints.
- A certificate is requested *in each region* for the API endpoints. While the certificates are being issued for the to protect the same domain and subdomains, this is **required in each region** because [ACM's certs are region-specific](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-regional-api-custom-domain-create.html). Once the certificates are issued, they can be assigned to the custom domains setup for each region's API Gateways.
- [CloudFront distributions require using certificates issued in the us-east-1 region](https://docs.aws.amazon.com/acm/latest/userguide/acm-regions.html). Because of this requirement, the voting UI static website that is hosted on S3 with CloudFront uses the certificate issued in the `us-east-1` region.
- [DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-validate-dns.html) is used for domain authentication.
- Certificates are only requested for the domains/subdomains that are used to [slightly reduce the risk that wildcard certs can introduce](https://www.cloudconformity.com/conformity-rules/ACM/wildcard-domain-name.html).

### X-Ray

- X-Ray is enabled on the API Gateway for improved visibility into how the Gateway is working. It's using the default trace sample rate of 5%.
- X-Ray support for Ruby in Lambda is [coming soon](https://aws.amazon.com/about-aws/whats-new/2018/11/aws-lambda-supports-ruby/), so is unfortunately not enabled.

## Election simulation

The `scripts` directory contains a few Ruby scripts that can be used to load the DynamoDB tables with sample voters and voter file data. Additionally, there are scripts that are used to simulate voting that would occur during voting. Be sure to change the region and profile name in the scripts to your own if you plan to use them.

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
- `generate_registered_voters.rb` - Generates just over 1 million sample voters with unique voter ids. This is 1% of the number of votes cast in the 2016 Presidential Election. Outputs to the `data` directory.
- `load_registered_voters.rb` - Loads in batches the sample voters generated in the above script into the `Voters` DynamoDB table.
- `populate_results_table.rb` - Populates the `results` table with base data on each state and candidate. As the votes are cast and the Lambda functions run, the counts are incremented.
- `generate_votes.rb` - Simulates votes being cast for the sample voters generated above. The votes cast in the simulation match the actual split of votes cast for each candidate in each state (but at 1% of what was actually cast).

### Metrics

The `generate_votes.rb` script will simulate votes being cast. With this script running on my MacBook Pro running in a coffee shop, this took about 25 minutes to send out the 1.3 million HTTP requests to the API Gateway.

Below are screenshots from CloudWatch showing how the various AWS resources reacted to the incoming sample votes.

#### API Gateway

![useast1count](assets/api-gateway-us-east-1-request-count.png?raw=true "us-east-1 request count")

![uswest1count](assets/api-gateway-us-west-1-request-count.png?raw=true "us-west-1 request count")

![gatewaylatency](assets/api-gateway-latency.png?raw=true "latency")

#### DynamoDB

![units](assets/dynamodb-units.png?raw=true "units")

![replication latency](assets/dynamodb-replication-latency.png?raw=true "latency")

![table latency](assets/dynamodb-table-latency.png?raw=true "latency")

#### Lambda

![stats](assets/lambda-stats.png?raw=true "lambda stats")

#### SQS

![stats](assets/sqs-stats.png?raw=true "sqs stats")

#### X-Ray

![xray](assets/xray.png?raw=true "xray")

#### Billing

The total cost of running the simulation was $34.05. A detailed breakdown of all the costs involved [can be viewed here](assets/aws-bill-merged.jpg). There are different tiers involved based on usage for some of these services. This means that the costs involved for running this with the 137 million voters in the 2016 Presidential Election would not simply be 100 times this amount. For example, Lambda and DynamoDB costs were low because the majority of requests were still in the free tier.

By looking at the pricing for each service, we would be able to getting a pretty good estimate of costs though:
  - 137.5 million voters in 2016 * $3.50 per million requests with API Gateway = $481.25 on API Gateway
  - 137.5 million * $0.40 per million SQS messages = $55 on SQS messages
  - 137.5 million * $0.20 per million Lambda requests * 2 Lambda functions = $55 on Lambda requests
  - 102443 GB-seconds at 1% of voters. Multiply this by 100 for the full number of voters is 10244300 GB-seconds * $0.00001667 per GB-second = $170.

A things to note:

- Domain registration was $12 (35%).
- 2,834,386 SQS requests was $1.13 (3%)
- $4.82 (14%) was because I went above the free tier on DynamoDB. I'd cranked this up high to load the million voters into the DynamoDB `Voters` table without throttling. I also loaded the table twice.
- Data Transfer was $0.20 (0.6%).
- $10.25 (30%) was the API Gateway. During the simulation I ended up sending 2,929,659 requests. I did a few practice runs, so this is higher than the number of voters.
- $0.26 (0.7%) was Lambda.
- KMS was $1.15 (3%) and primarily from KMS requests.

## Website

A static website hosted on S3 with a simple example UI of how voters interact with the API is located at https://election.tylerpearson.cloud.

A JSON API endpoint with real-time results is located at https://api.election.tylerpearson.cloud/votes.

## Disclaimers

- This demo doesn't take into account whether online/electronic voting *should* be done, just how it *could* be done with current AWS services. The web [is](https://www.chicagotribune.com/suburbs/highland-park/news/ct-hpn-election-integrity-forum-tl-1102-20171031-story.html) [full](https://engineering.stanford.edu/magazine/article/david-dill-why-online-voting-danger-democracy) [of](https://www.vox.com/policy-and-politics/2018/8/13/17683666/florida-voting-system-hack-children) [opinions](https://www.politico.com/story/2018/10/13/west-virginia-voting-app-security-846130), if you're looking for that.
- In something as critical as a Presidential election, it would likely make sense to use all four regions that currently exist in the United States. Tweak `main.tf` to add additional regions.
- The code currently doesn't support write-in votes and assumes that five presidential candidates (Trump, Clinton, Johnson, Stein, McMullin) are on the ballot in every state, which isn't the case.
- While the results are broken down by state, this demo assumes shifting the management of the election to some sort of central federal agency that manages voting across the country instead of the individual states' responsibility.
- There's a ton of additional functionality and services that could be setup and used (CloudWatch alarms for notifications of issues, GuardDuty and CloudTrail for security, etc.) that isn't included. I timeboxed many parts of this demo in the sake being able to have a finishing point.

