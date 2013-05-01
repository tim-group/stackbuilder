require 'stacks/namespace'
require 'uri'

class Stacks::ProxyVHost
  attr_reader :aliases
  attr_reader :vhost_fqdn
  attr_reader :service
  attr_reader :redirects

  def initialize(vhost_fqdn, service, &block)
    @vhost_fqdn = vhost_fqdn
    @service = service
    @aliases = []
    @redirects = []
    self.instance_eval &block
  end

  def with_alias(alias_fqdn)
    @aliases << alias_fqdn
  end

  def with_redirect(redirect_fqdn)
    @redirects << redirect_fqdn
  end
end

