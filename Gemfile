source 'https://rubygems.org'

gem 'collimator', '0.0.3'
gem 'mcollective-client', '2.8.2'
gem 'puppet', '6.13.0'
gem 'rspec', '3.3.0' # used by stacks test command
gem 'rubocop', '0.32.1'
gem 'orc', :git => 'https://github.com/tim-group/orc.git', :ref => '2daa527d5a251e9cf2396ba5282a0a4b23e5500c'

group :development do
  gem 'ci_reporter_rspec', '1.0.0'
  gem 'pry'
  gem 'pry-byebug'
  gem 'hashdiff'
  gem 'rake', '10.1.0'
  gem 'syck' if RUBY_VERSION.split('.').first.to_i > 1
end
