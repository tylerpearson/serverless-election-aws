require 'json'
require 'time'

def handler(event:, context:)

  # TODO: Actually test availability of SQS and DynamoDB, not just API Gateway and Lambda.
  # Any health check that reaches this function will return a 200

  status_code = 200
  region = context.invoked_function_arn.split(':')[3]
  current_time = Time.now.utc.iso8601

  body = { message: "Success from #{region} at #{current_time}" }

  response = {
    "isBase64Encoded": false,
    "statusCode": status_code,
    "headers": {
      "Access-Control-Allow-Origin": "*",
      "Content-Type": "application/json"
    },
    "body": body.to_json
  }

  puts response

  response
end
