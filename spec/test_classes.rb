require 'resolv'

class TestAppDeployer
  def initialize(version)
    @version = version
  end

  def query_cmdb_for(_spec)
    fail "Not found" if @version.nil?
    { :target_version => @version }
  end
end

class MyTestDnsResolver
  def initialize(ip_address_map)
    @ip_address_map = ip_address_map
  end

  def lookup(fqdn)
    Resolv::IPv4.create(@ip_address_map[fqdn])
  rescue ArgumentError
    raise Resolv::ResolvError, "no address for #{fqdn}"
  end
end

class TestHieraProvider
  def initialize(data)
    @data = data
  end

  def lookup(_machineset, key, default_value = nil)
    @data.key?(key) ? @data[key] : default_value
  end
end
