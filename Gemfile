source 'https://rubygems.org'

gem 'collimator', '0.0.3'
gem 'mcollective-client', '2.8.2'
gem 'puppet', '3.7.5'
gem 'rspec', '3.3.0' # used by stacks test command
gem 'rubocop', '0.32.1'

group :development do
  gem 'ci_reporter_rspec', '1.0.0'
  gem 'pry'
  gem 'pry-byebug'
  gem 'rake', '10.1.0'
  gem 'sync' if Gem::Version.new(RUBY_VERSION) > Gem::Version.new('2.6')
  gem 'syck' if RUBY_VERSION.split('.').first.to_i > 1
end
