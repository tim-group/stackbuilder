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

class AllocatingDnsResolver
  def initialize
    @current = [10, 1, 2, 0]
    @ip_address_map = {}
  end

  def lookup(fqdn)
    if @ip_address_map[fqdn]
      @ip_address_map[fqdn]
    else
      @current = inc(@current)
      @ip_address_map[fqdn] = Resolv::IPv4.create(@current.join('.'))
    end
  rescue ArgumentError
    raise Resolv::ResolvError, "no address for #{fqdn}"
  end

  def inc(octets)
    if octets[-1] < 255
      octets[0, octets.length - 1] + [octets[-1] + 1]
    elsif octets.length > 1
      inc(octets[0, octets.length - 1]) + [0]
    else
      fail('Unable to allocate IP address, ran out of octets')
    end
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
