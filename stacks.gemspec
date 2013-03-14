require 'rake'

hash = `git rev-parse --short HEAD`.chomp
v_part= ENV['BUILD_NUMBER'] || "0.pre.#{hash}"
version = "0.0.#{v_part}"

Gem::Specification.new do |s|
  s.name = "stacks"
  s.date = Time.now.strftime("%Y-%m-%d")
  s.version = version
  s.authors = ["TIMGroup Infrastructure Team"]
  s.default_executable = %q{}
  s.description = %q{}
  s.email = %q{}
  s.executables = Dir.new("bin").entries.reject { |entry| entry == '.' || entry == '..' } # Rake and Ruby - WINNING TEAM
  s.extra_rdoc_files = ["KNOWN-ISSUES"]
  s.files = Dir.glob("lib/**/*")
  s.require_paths = ["lib"]
  s.summary = %q{a tool for generating "stacks" that form software services}
  s.test_files = []
end
