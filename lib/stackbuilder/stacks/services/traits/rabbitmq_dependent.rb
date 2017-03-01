module Stacks::Services::RabbitMqDependent
  RabbitMq = Struct.new(:username, :password_hiera_key)

  def self.extended(object)
    object.configure
  end

  def configure
  end

  def create_rabbitmq_config(username)
    RabbitMq.new(username, password_hiera_key(username))
  end

  def configure_rabbitmq(username)
    @rabbitmq = RabbitMq.new(username, password_hiera_key(username))
  end

  def rabbitmq_config
    @rabbitmq
  end

  private

  def password_hiera_key(username)
    "#{@environment.name}/#{username}/messaging_password"
  end
end
