RSpec::Matchers.define :be_in_group do |expected_group|
  match do |server|
    server.to_enc['role::http_app']['group'] == expected_group
  end

  failure_message do |server|
    enc = server.to_enc
    "expected that #{server.hostname} would be in group #{expected_group} " \
      "but was in group #{enc['role::http_app']['group']}"
  end

  failure_message_when_negated do |_actual|
  end

  #  description do
  #  end
end
