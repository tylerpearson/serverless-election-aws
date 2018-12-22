require 'csv'
require 'json'
require 'aws-sdk-dynamodb'
require 'securerandom'

dynamodb = Aws::DynamoDB::Client.new(region: 'us-west-1',
                                     profile: 'tyler-personal-election')

skipped_count = 0
loaded_count = 0

voters = JSON.load File.new("data/voters.json")

voters.each_with_index do |voter_info, index|

  puts index if index % 1000 == 0

  params = {
    table_name: 'voters',
    item: voter_info
  }

  begin
    # todo: change to batch insert
    result = dynamodb.put_item(params)
    loaded_count += 1
    # puts voter_info.to_json
  rescue  Aws::DynamoDB::Errors::ServiceError => error
    puts 'Unable to add voter'
    puts voter_info.to_json
    puts error.message
  end

end


puts "========="
puts "Loaded voters: #{loaded_count}"
puts "Skipped voters: #{skipped_count}"
