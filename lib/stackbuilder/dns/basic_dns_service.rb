require 'stackbuilder/compute/controller'

module StackBuilder::DNS
end

class StackBuilder::DNS::BasicDNSService
  def allocate(specs)
    do_ip_allocations('allocate', specs)
    do_cnames('add', specs)
  end

  def free(specs)
    do_ip_allocations('free', specs)
    do_cnames('remove', specs)
  end

  def do_ip_allocations(type, specs)
    method = "#{type}_ips".to_sym
    computecontroller = Compute::Controller.new
    computecontroller.send(method, specs) do
      on :success do |vm|
        logger(Logger::INFO) { "#{vm} #{type} IP successfully" }
      end
      on :failure do |vm, msg|
        logger(Logger::ERROR) { "#{vm} failed to #{type} IP: #{msg}" }
      end
      on :unaccounted do |vm|
        logger(Logger::ERROR) { "#{vm} was unaccounted for" }
      end
      has :failure do
        fail "some machines failed to #{type} IPs"
      end
    end
  end

  def do_cnames(type, specs)
    method = "#{type}_cnames".to_sym
    computecontroller = Compute::Controller.new
    computecontroller.send(method, specs) do
      on :success do |vm|
        logger(Logger::INFO) { "#{vm} #{type} CNAME successfully" }
      end
      on :failure do |vm, msg|
        logger(Logger::ERROR) { "#{vm} failed to #{type} CNAME entry: #{msg}" }
      end
      on :unaccounted do |vm|
        logger(Logger::ERROR) { "#{vm} was unaccounted for" }
      end
      has :failure do
        fail "some machines failed to #{type} CNAMEs"
      end
    end
  end
end
