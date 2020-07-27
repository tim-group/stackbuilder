source 'https://rubygems.org'

gem 'collimator', '0.0.3'
gem 'mcollective-client', '2.8.2'
gem 'puppet', '3.7.5'
gem 'rspec', '3.3.0' # used by stacks test command
gem 'rubocop', '0.32.1'
gem 'orc', :git => 'https://github.com/tim-group/orc.git', :ref => '9bd34ed0b9d7db51dd84cd944e7e4d117d5b79c2'

group :development do
  gem 'ci_reporter_rspec', '1.0.0'
  gem 'pry'
  gem 'pry-byebug'
  gem 'hashdiff'
  gem 'rake', '10.1.0'
  gem 'syck' if RUBY_VERSION.split('.').first.to_i > 1
end
