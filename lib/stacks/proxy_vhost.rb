require 'stacks/namespace'
require 'uri'

class Stacks::ProxyVHost
  attr_reader :aliases
  attr_reader :vhost_fqdn
  attr_reader :service
  attr_reader :redirects
  attr_reader :proxy_pass_rules
  attr_reader :properties
  attr_reader :type
  attr_reader :cert

  def initialize(vhost_fqdn, service, type = 'default', &block)
    @vhost_fqdn = vhost_fqdn
    @service = service
    @aliases = []
    @redirects = []
    @proxy_pass_rules = {}
    @type = type
    @properties = {}
    @cert = 'wildcard_timgroup_com'
    instance_eval(&block) if block
  end

  def with_alias(alias_fqdn)
    @aliases << alias_fqdn
  end

  def with_redirect(redirect_fqdn)
    @redirects << redirect_fqdn
  end

  def pass(proxy_pass_rule)
    @proxy_pass_rules.merge!(proxy_pass_rule)
  end

  def with_cert(cert_name)
    @cert = cert_name
  end

  def vhost_properties(properties)
    @properties.merge!(properties)
  end
end
