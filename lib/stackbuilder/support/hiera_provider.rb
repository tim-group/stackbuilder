require 'stackbuilder/support/namespace'
require 'tmpdir'
require 'yaml'
require 'open3'

class Support::HieraProvider
  def initialize(opts)
    fail('Origin option is required') if !opts[:origin]
    @local_path = opts[:local_path] || '/tmp/stacks-puppet-repo'
    @origin = opts[:origin].start_with?('/') ? 'file://' + opts[:origin] : opts[:origin]
  end

  def hieradata
    @hieradata ||= fetch_hieradata
  end

  def lookup(scope, key, default_value = nil)
    %w(domain hostname environment stackname).each do |s|
      fail("Missing variable - Hiera lookup requires #{s} in scope") if !scope[s]
    end

    hieradata.fetch(scope['domain'], {}).fetch(scope['hostname'], {}).fetch(key, nil) ||
      hieradata.fetch(scope['domain'], {}).fetch(scope['environment'], {}).fetch(key, nil) ||
      hieradata.fetch("logicalenv_#{scope['environment']}", {}).fetch(key, nil) ||
      hieradata.fetch("domain_#{scope['domain']}", {}).fetch(key, nil) ||
      hieradata.fetch('stacks', {}).fetch(scope['stackname'], {}).fetch(key, nil) ||
      hieradata.fetch('dbrights', {}).fetch(key, nil) ||
      hieradata.fetch('secrets', {}).fetch(key, nil) ||
      hieradata.fetch('common', {}).fetch(key, nil) ||
      default_value ||
      fail("Could not find data item #{key} in any Hiera data file and no default supplied")
  end

  def fetch_hieradata
    FileUtils.remove_dir(@local_path, true)
    _stdout_str, stderr_str, status = Open3.capture3('git', 'clone', '--quiet', '--depth', '1', @origin, @local_path)
    fail "Unable to clone '#{@origin}' - error: '#{stderr_str}'" if !status.success?

    the_hieradata = {}
    Dir.glob("#{@local_path}/**/*.yaml").each do |f|
      contents = YAML.load(File.open(f))
      the_hieradata[File.basename(f, File.extname(f))] = contents
    end

    the_hieradata
  end
end
