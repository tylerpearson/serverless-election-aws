require 'json'
require 'time'
require 'aws-sdk-dynamodb'

def state_array
  %w(AK AL AR AZ CA CO CT DC DE FL GA HI IA ID IL IN KS KY LA MA MD ME MI MN MO MS MT NC ND NE NH NJ NM NV NY OH OK OR PA RI SC SD TN TX UT VA VT WA WI WV WY)
end

def handler(event:, context:)
  dynamodb = Aws::DynamoDB::Resource.new

  table = dynamodb.table('results')

  scan_output = table.scan({
    select: "SPECIFIC_ATTRIBUTES",
    attributes_to_get: ["count", "candidate", "state"],
  })

  results = []

  state_array.each do |state|
    state_results = scan_output.items
                      .select { |item| item['state'] == state }
                      .map { |item| { candidate: item['candidate'], count: item['count'].to_i } }
    results << { state: state,
                 total_count: state_results.inject(0) { |s, h| s + h[:count] },
                 results: state_results }
  end

  response = {
    "isBase64Encoded": false,
    "statusCode": 200,
    "headers": {
      "Access-Control-Allow-Origin": "*"
    },
    "body": results.to_json
  }

  puts response

  response
end
