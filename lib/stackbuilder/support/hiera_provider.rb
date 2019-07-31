require 'stackbuilder/support/namespace'
require 'tmpdir'
require 'yaml'
require 'open3'

class Support::HieraProvider
  HIERARCHY = [
    lambda { |hieradata, scope| hieradata.fetch(scope['domain'], {}).fetch(scope['hostname'], {}) },
    lambda { |hieradata, scope| hieradata.fetch(scope['domain'], {}).fetch(scope['logicalenv'], {}) },
    lambda { |hieradata, scope| hieradata.fetch("logicalenv_#{scope['logicalenv']}", {}) },
    lambda { |hieradata, scope| hieradata.fetch("domain_#{scope['domain']}", {}) },
    lambda { |hieradata, scope| hieradata.fetch('stacks', {}).fetch(scope['stackname'], {}) },
    lambda { |hieradata, _scope| hieradata.fetch('dbrights', {}) },
    lambda { |hieradata, _scope| hieradata.fetch('secrets', {}) },
    lambda { |hieradata, _scope| hieradata.fetch('common', {}) }
  ]

  def initialize(opts)
    fail('Origin option is required') if !opts[:origin]
    @local_path = opts[:local_path] || '/tmp/stacks-puppet-repo'
    @origin = opts[:origin].start_with?('/') ? 'file://' + opts[:origin] : opts[:origin]
  end

  def hieradata
    @hieradata ||= fetch_hieradata
  end

  def lookup(scope, key, default_value = nil)
    %w(domain hostname logicalenv stackname).each do |s|
      fail("Missing variable - Hiera lookup requires #{s} in scope") if !scope[s]
    end

    HIERARCHY.each do |x|
      return x.call(hieradata, scope)[key] if x.call(hieradata, scope).key?(key)
    end

    return default_value if !default_value.nil?

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
