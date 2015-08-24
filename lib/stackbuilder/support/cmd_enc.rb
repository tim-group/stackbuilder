module CMDEnc
  require 'stackbuilder/support/cmd'

  def self.enc(_argv)
    machine_def = CMD.stack

    if machine_def.respond_to?(:to_enc)
      require 'stackbuilder/support/zamls'
      puts ZAMLS.to_zamls(machine_def.to_enc)
    else
      logger(Logger::FATAL) { "\"#{$options[:stack]}\" is not a machine fqdn" }
      exit 1
    end
  end
end
