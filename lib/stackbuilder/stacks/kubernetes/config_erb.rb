class ConfigERB < ERB
  attr_reader :used_secrets

  def initialize(template, vars, hiera_provider)
    super(template, nil, '-')
    vars.each { |k, v| instance_variable_set("@#{k}", v) }
    @vars = vars
    @hiera_provider = hiera_provider
    @used_secrets = {}
  end

  def hiera(key, default = nil)
    value = @hiera_provider.lookup(@vars, key, default)
    fail "The hiera value for #{key} is encrypted. \
e secret(#{key}) instead of hiera(#{key}) in appconfig" if value.is_a?(String) && value.match(/^ENC\[GPG/)
    value
  end

  def secret(key, index = nil)
    secret_name = key.gsub(/[^a-zA-Z0-9]/, '_')
    secret_name += "_#{index}" unless index.nil?
    @used_secrets[key] = secret_name
    "{SECRET:#{secret_name}}"
  end

  def render
    result(binding)
  end
end
