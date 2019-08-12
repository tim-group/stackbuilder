require 'resolv'

class Support::DnsResolver
  def initialize
    @resolver = Resolv::DNS.new
  end

  def lookup(host)
    @resolver.getaddress(host)
  rescue
    "NOT YET ASSIGNED (#{host})"
  end
end
