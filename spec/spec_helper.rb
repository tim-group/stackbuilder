# generate a spec coverage test if 'simplecov' is installed
# note this adds approx 1 second to 'rake spec'.
if !ENV['STACKS_RSPEC_SEPARATE'] # doesn't make sense with STACKS_RSPEC_SEPARATE enabled
  if RUBY_VERSION[0, 3] != '1.8' # XXX remove once ruby1.8 is abandoned
    begin
      require 'simplecov'
      SimpleCov.start
    rescue Gem::LoadError
      puts "simplecov not installed, not generating coverage reports"
    end
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

# commented out code can be used to find long running specs
RSpec.configure do |config|
  config.before :each do
    # @t1 = Time.now
    silence_output
  end

  config.after :each do
    enable_output
    # printf("%0.2f seconds in %s\n", Time.now - @t1, example.metadata[:example_group][:file_path])
  end
end
