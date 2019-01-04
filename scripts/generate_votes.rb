require 'json'
require 'net/http'
require 'typhoeus'

RESULTS_JSON_URL = "http://data.cnn.com/ELECTION/2016/full/P.full.json"

# http://data.cnn.com/ELECTION/2016/full/P.full.json

results = {}

# save this, the results aren't going to change
url = 'http://data.cnn.com/ELECTION/2016/full/P.full.json'
uri = URI(url)
response = Net::HTTP.get(uri)
voting_results = JSON.parse(response)

voting_results['races'].each do |race|
  next if race['state'] == "UNITED STATES"

  state_id = race['raceid'][0,2]
  results[state_id] = {}

  race['candidates'].each do |candidate|
    results[state_id]["#{candidate['fname']} #{candidate['lname']}"] = candidate['vpct']
  end

end


def select_candidate(weighted)
  sum = weighted.inject(0) do |sum, item_and_weight|
    sum += item_and_weight[1]
  end
  target = rand(sum)
  weighted.each do |item, weight|
    return item if target <= weight
    target -= weight
  end
end


voters = JSON.load File.new("data/voters-2.json")

hydra = Typhoeus::Hydra.new


voters.each_with_index do |voter_info, index|
  vote = { "id": voter_info['id'],
           "candidate": select_candidate(results[voter_info['state']]) }

  # api_url = "https://api.election.tylerpearson.cloud/votes"

  # swap between east coast and west coast so the latency based routing doesn't
  # send requests all to the same api gateway
  api_url = ["https://8wyq0geyoh.execute-api.us-east-1.amazonaws.com/production/votes",
             "https://6l6k7779ka.execute-api.us-west-1.amazonaws.com/production/votes"].sample

  retries ||= 0
  request = Typhoeus::Request.new(api_url, method: :post, headers: { 'Content-Type'=> 'application/json' }, body: vote.to_json)
  hydra.queue(request)

  if index % 1_000 == 0
    puts "#{index} to #{api_url[34,4]} endpoint"
    # puts result
  end

end

hydra.run
