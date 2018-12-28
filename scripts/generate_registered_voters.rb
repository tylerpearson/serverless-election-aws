require 'csv'
require 'aws-sdk-dynamodb'
require 'securerandom'
require 'faker'

dynamodb = Aws::DynamoDB::Client.new(region: 'us-west-1',
                                     profile: 'tyler-personal-election')

VOTERS_FILE_NAME = 'voters.json'

# Total nubmer of votes cast in 2016 for the Presidential election
TOTAL_VOTES_2016 = 136_669_237
SAMPLE_TOTAL_VOTES = (TOTAL_VOTES_2016 * 0.01).to_i

# Number of votes per state, so the sample is split with an accurate representation
STATES_VOTES_TOTALS = {
  AL: 2_123_372,
  AK: 318_608,
  AZ: 2_573_165,
  AR: 1_130_635,
  CA: 14_181_595,
  CO: 2_780_247,
  CT: 1_644_920,
  DE: 443_814,
  DC: 311_268,
  FL: 9_420_039,
  GA: 4_114_732,
  HI: 428_937,
  ID: 690_255,
  IL: 5_536_424,
  IN: 2_734_958,
  IA: 1_566_031,
  KS: 1_184_402,
  KY: 1_924_149,
  LA: 2_029_032,
  ME: 747_927,
  MD: 2_781_446,
  MA: 3_325_046,
  MI: 4_799_284,
  MN: 2_944_813,
  MS: 1_209_357,
  MO: 2_808_605,
  MT: 497_147,
  NE: 844_227,
  NV: 1_125_385,
  NH: 744_296,
  NJ: 3_874_046,
  NM: 798_319,
  NY: 7_721_453,
  NC: 4_741_564,
  ND: 344_360,
  OH: 5_496_487,
  OK: 1_452_992,
  OR: 2_001_336,
  PA: 6_165_478,
  RI: 464_144,
  SC: 2_103_027,
  SD: 370_093,
  TN: 2_508_027,
  TX: 8_969_226,
  UT: 1_131_430,
  VT: 315_067,
  VA: 3_984_631,
  WA: 3_317_019,
  WV: 714_423,
  WI: 2_976_150,
  WY: 255_849
}

# select a state for the voter based on the percentage of total votes by state
def select_state
  weighted = STATES_VOTES_TOTALS
  sum = weighted.inject(0) do |sum, item_and_weight|
    sum += item_and_weight[1]
  end
  target = rand(sum)
  weighted.each do |item, weight|
    return item if target <= weight
    target -= weight
  end
end


# Grabbed from Rails to choose letters that don't look the same to make it easier for voters to enter the correct characters
# https://github.com/rails/rails/blob/94b5cd3a20edadd6f6b8cf0bdf1a4d4919df86cb/activesupport/lib/active_support/core_ext/securerandom.rb#L18
module SecureRandom
  BASE58_ALPHABET = ("0".."9").to_a + ("A".."Z").to_a + ("a".."z").to_a - ["0", "O", "I", "l"]
  def self.base58(n = 16)
    SecureRandom.random_bytes(n).unpack("C*").map do |byte|
      idx = byte % 64
      idx = SecureRandom.random_number(58) if idx >= 58
      BASE58_ALPHABET[idx]
    end.join
  end
end


puts "Sampling #{SAMPLE_TOTAL_VOTES}"


voters = []

SAMPLE_TOTAL_VOTES.times do |id|
  state = select_state

  voter = {
    first_name: Faker::Name.first_name,
    last_name: Faker::Name.last_name,
    address: "#{Faker::Address.street_address}, #{Faker::Address.city}, #{state} #{Faker::Address.postcode}",
    voter_id: SecureRandom.base58.scan(/.{5}/).join('-'),
    state: state
  }
  voters << voter

  if id % 100_000 == 0
    # Save to disk every 100_000 voters
    File.open("data/#{VOTERS_FILE_NAME}", "w") do |f|
      f.write(voters.to_json)
    end
    puts "#{((id.to_f / SAMPLE_TOTAL_VOTES) * 100).round(2)}% of #{SAMPLE_TOTAL_VOTES} generated"
  end
end

File.open("data/#{VOTERS_FILE_NAME}", "w") do |f|
  f.write(voters.to_json)
end
