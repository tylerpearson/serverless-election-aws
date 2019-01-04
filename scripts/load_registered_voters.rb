require 'csv'
require 'json'
require 'aws-sdk-dynamodb'
require 'securerandom'

dynamodb = Aws::DynamoDB::Client.new(region: 'us-west-1',
                                     profile: 'election-simulation')

skipped_count = 0
loaded_count = 0

voters = JSON.load(File.new("data/voters-2.json"))

index = 0

voters.each_slice(25).to_a.each do |voters_info|
  puts index if index % 1000 == 0

  items_to_insert = []

  voters_info.each do |vote|
    items_to_insert <<  { put_request: { item: vote } }
  end

  begin
    resp = dynamodb.batch_write_item({
      request_items: {
        'Voters' => items_to_insert,
      },
      return_consumed_capacity: "NONE",
      return_item_collection_metrics: "SIZE",
    })
    index += 25
    # puts voter_info.to_json
  rescue  Aws::DynamoDB::Errors::ServiceError => error
    puts 'Unable to add voter'
    puts error.message
  end

end


puts "========="
puts "Loaded voters: #{index}"
puts "Skipped voters: #{skipped_count}"
