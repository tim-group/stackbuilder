# Facter.value('owner') is very slow, so do this instead (recreates logic from puppet)
# caching `hostname` in @@localhost_hostname is a major speedup (0.5 seconds as of 24.04.2015 on a dev box)
# rubocop:disable Style/ClassVars
module OwnerFact
  def self.owner_fact
    @@localhost_hostname = `hostname` if !defined? @@localhost_hostname
    case @@localhost_hostname
    when /^\w{3}-dev-(\w+)/            then $1
    when /^(\w+)-desktop/              then $1
    when /^dev-puppetserver-\d+-(\w+)$/ then $1
    else 'OWNER-FACT-NOT-FOUND'
    end
  end
end
# rubocop:enable Style/ClassVars
