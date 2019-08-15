require 'stackbuilder/stacks/namespace'

module Stacks::Services::S3ProxyService
  def self.extended(object)
    object.configure
  end

  def configure
    on_bind { validate_only_has_one_instance }
  end

  def endpoints(_dependent_service, _fabric)
    [{
      :port => 80,
      :fqdns => [children.first.prod_fqdn]
    }]
  end

  def config_params(_dependant, _fabric, _dependent_service)
    {
      's3.proxyhost' => children.first.prod_fqdn,
      's3.proxyport' => 80
    }
  end

  def validate_only_has_one_instance
    fail 's3_proxy_service does not support more than one instance' if instances > 1
  end
end
