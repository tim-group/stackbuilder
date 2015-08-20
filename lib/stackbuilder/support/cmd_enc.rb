module CMDEnc
  def self.enc(argv)
    require 'stackbuilder/support/zamls'

    if argv.size != 1 then
      logger(Logger::FATAL) { 'enc takes exactly one argument: a fqdn' }
      exit 1
    end
    name = argv.shift

    machine_def = $factory.inventory.find(name)
    if machine_def.nil? then
      logger(Logger::FATAL) { "\"#{name}\" not found" }
      exit 1
    end
    puts ZAMLS.to_zamls(machine_def.to_enc)
  end
end
