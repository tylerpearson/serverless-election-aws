require 'csv'
require 'json'
require 'aws-sdk-dynamodb'
require 'securerandom'

dynamodb = Aws::DynamoDB::Client.new(region: 'us-west-1',
                                     profile: 'election-simulation')


candidates = ["Donald Trump", "Hillary Clinton", "Gary Johnson", "Jill Stein", "Evan McMullin"]

def state_array
  %w(AK AL AR AZ CA CO CT DC DE FL GA HI IA ID IL IN KS KY LA MA MD ME MI MN MO MS MT NC ND NE NH NJ NM NV NY OH OK OR PA RI SC SD TN TX UT VA VT WA WI WV WY)
end


state_array.each_with_index do |state, index|

  candidates.each do |name|
    puts "#{name} #{state}"

    state_item = {
      candidate: name,
      state: state,
      count: 0
    }

    params = {
      table_name: 'Results',
      item: state_item
    }

    begin
      result = dynamodb.put_item(params)
    rescue  Aws::DynamoDB::Errors::ServiceError => error
      puts 'Unable to add state'
      puts params.to_json
      puts error.message
    end

  end

end

puts "finished"
