module Stacks::Services::SharedAppLikeThing
  attr_accessor :use_ha_mysql_ordering
  attr_accessor :application
  alias_method :database_application_name, :application

  def self.extended(object)
    object.configure
  end

  def configure
    @use_ha_mysql_ordering = false
  end

  def database_username
    if @kubernetes
      @environment.short_name + @short_name
    else
      @application
    end
  end
end
