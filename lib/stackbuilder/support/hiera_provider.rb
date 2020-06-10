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
    the_hieradata = {}
    Dir.mktmpdir do |local_path|
      _stdout_str, stderr_str, status = Open3.capture3('git', 'clone', '--quiet', '--depth', '1', @origin, local_path)
      fail "Unable to clone '#{@origin}' - error: '#{stderr_str}'" if !status.success?

      Dir.glob("#{local_path}/hieradata/**/*.yaml").each do |f|
        contents = YAML.load(File.open(f))
        relative_dirs = File.dirname(f).sub(/^#{local_path}\/hieradata/, '').sub(/^\//, '')

        hash_bury(the_hieradata, *relative_dirs.split('/').push(File.basename(f, File.extname(f))).push(contents))
      end
    end

    the_hieradata
  end

  def hash_bury(hash, *args)
    if args.count < 2
      fail ArgumentError "2 or more arguments required"
    elsif args.count == 2
      hash[args[0]] = args[1]
    else
      arg = args.shift
      hash[arg] = {} unless hash[arg]
      hash_bury(hash[arg], *args) unless args.empty?
    end
    hash
  end
end
