# generate a spec coverage test if 'simplecov' is installed
# note this adds approx 1 second to 'rake spec'.
if !ENV['STACKS_RSPEC_SEPARATE'] # doesn't make sense with STACKS_RSPEC_SEPARATE enabled
  begin
    require 'simplecov'
    SimpleCov.start
  rescue Gem::LoadError
    puts "simplecov not installed, not generating coverage reports"
  end
end

def silence_output
  @orig_stderr = $stderr
  @orig_stdout = $stdout

  $stderr = File.new('/dev/null', 'w')
  $stdout = File.new('/dev/null', 'w')
end

def enable_output
  $stderr = @orig_stderr
  $stdout = @orig_stdout
  @orig_stderr = nil
  @orig_stdout = nil
end

RSpec.configure do |config|
  config.before :each do
    silence_output
  end

  config.after :each do
    enable_output
  end
end
