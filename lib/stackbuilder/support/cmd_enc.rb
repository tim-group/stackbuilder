module CMDEnc
  def self.enc
    require 'stackbuilder/support/cmd'
    machine_def = Opt.stack

    if machine_def.respond_to?(:to_enc)
      require 'stackbuilder/support/zamls'
      puts ZAMLS.to_zamls(machine_def.to_enc)
    else
      logger(Logger::FATAL) { "\"#{$options[:stack]}\" is not a machine fqdn" }
      exit 1
    end
  end
end
