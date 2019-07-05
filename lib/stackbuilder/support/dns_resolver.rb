require 'resolv'

class Support::DnsResolver
  def initialize
    @resolver = Resolv::DNS.new
  end

  def lookup(host)
    @resolver.getaddress(host)
  end
end
