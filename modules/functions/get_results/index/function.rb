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
    state_results = scan_output.items.select { |item| item['state'] == state }

    state_results =  state_results.map do |item|
                        { candidate: item['candidate'],
                          count: item['count'].to_i }
                      end

    total_count = state_results.inject(0) { |s, h| s + h[:count] }

    state_results = state_results.map do |state|
      state.merge!({ percentage: "#{((state[:count].to_f / total_count.to_f) * 100.0).round}%" })
    end

    results << { state: state,
                 disclaimer: "These vote counts are estimates. Visit https://github.com/tylerpearson/serverless-election-aws for more info.",
                 total_count: total_count,
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
