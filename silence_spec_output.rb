# Redirects stderr and stdout to /dev/null.
def spec_silence_output
  @orig_stderr = $stderr
  @orig_stdout = $stdout

  $stderr = File.new('/dev/null', 'w')
  $stdout = File.new('/dev/null', 'w')
end

# Replace stdout and stderr so anything else is output correctly.
def spec_enable_output
  $stderr = @orig_stderr
  $stdout = @orig_stdout
  @orig_stderr = nil
  @orig_stdout = nil
end
