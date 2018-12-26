require 'json'
require 'time'
require 'aws-sdk-sqs'
require 'aws-sdk-dynamodb'

def handler(event:, context:)
  event_body = JSON.parse(event['body'])

  dynamo_client = Aws::DynamoDB::Client.new
  resp = dynamo_client.get_item({
    key: {
      'voter_id': event_body['voter_id']
    },
    table_name: ENV['VOTERS_DYNAMO_TABLE_NAME'],
    return_consumed_capacity: 'NONE'
  })

  if resp.item && resp.item['voted_at'].nil?
    sqs_client = Aws::SQS::Client.new
    resp = sqs_client.send_message({
      queue_url: ENV['VOTES_QUEUE_URL'],
      message_body: event_body.merge!({voted_at: Time.now.utc.iso8601}).to_json
    })
    status_code = 201
    body = {
      "success": true,
      "message": "Vote #{event_body['voter_id']} registered"
    }
  elsif resp.item && !resp.item['voted_at'].nil?
    status_code = 409
    body = {
      "success": false,
      "message": "#{event_body['voter_id']} submitted at vote at #{resp.item['voted_at']}"
    }
  else
    status_code = 404
    body = {
      "success": false,
      "message": "This voter id does not exist: #{event_body['voter_id']}"
    }
  end

  response = {
    "isBase64Encoded": false,
    "statusCode": status_code,
    "headers": {
      "Access-Control-Allow-Origin": "*"
    },
    "body": body.to_json
  }

  puts response

  response
end
