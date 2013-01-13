require 'rubygems'
require 'rspec'
require 'ci/reporter/rspec'

RSpec::Core::Runner.disable_autorun!
config = RSpec.configuration
config.color_enabled = true
describe 'hello' do
  it 'says init' do

  end
end

RSpec::Core::Runner.run(
  ['--format','CI::Reporter::RSpec'],
  $stderr,
  $stdout)


