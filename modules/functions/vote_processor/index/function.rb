require 'json'
require 'aws-sdk-sqs'
require 'aws-sdk-dynamodb'

def handler(event:, context:)
  dynamo_client = Aws::DynamoDB::Client.new

  event['Records'].each do |record|
    message = JSON.parse(record['body'])

    # https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/DynamoDB/Client.html#transact_write_items-instance_method
    save_response = dynamo_client.update_item({
      expression_attribute_names: {
        "#C" => "candidate",
        "#VA" => "voted_at"
      },
      expression_attribute_values: {
        ":c": message['candidate'],
        ":va": message['voted_at'],
      },
      key: {
        "id": message['id'],
      },
      return_values: "ALL_NEW",
      table_name: ENV['VOTERS_DYNAMO_TABLE_NAME'],
      update_expression: "SET #C = :c, #VA = :va"
    })


    state = save_response.attributes['state']
    candidate = save_response.attributes['candidate']

    results_response = dynamo_client.update_item({
      expression_attribute_names: {
        "#C" => "count"
      },
      expression_attribute_values: {
        ":a": 1,
      },
      key: {
        state: state,
        candidate: candidate
      },
      return_values: "UPDATED_NEW",
      table_name: ENV['RESULTS_DYNAMO_TABLE_NAME'],
      update_expression: "SET #C = #C + :a"
    })
  end

  puts save_response.attributes

end
