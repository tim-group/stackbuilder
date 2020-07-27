require 'hashdiff'

RSpec::Matchers.define :hash_eq do |expected|
  match do |actual|
    expect(expected).to eq(actual)
  end
  failure_message do |actual|
    diff = Hashdiff.diff(expected, actual)
    message = "Expected hashes to be identical, diff is:"
    diff.each do |change|
      message << "\n"
      case change[0]
      when "-"
        message << "- #{change[1]} => #{change[2]}"
      when "+"
        message << "+ #{change[1]} => #{change[2]}"
      when "~"
        message << "~ #{change[1]}: #{change[2]} -> #{change[3]}"
      end
    end
    message
  end
end
