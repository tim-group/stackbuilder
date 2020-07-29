module Stacks::Services::SharedAppLikeThing
  attr_accessor :use_ha_mysql_ordering
  attr_accessor :ha_mysql_ordering_exclude
  attr_accessor :application
  alias_method :database_application_name, :application

  def self.extended(object)
    object.configure
  end

  def configure
    @use_ha_mysql_ordering = false
    @ha_mysql_ordering_exclude = []
  end

  def database_username
    if @kubernetes
      @environment.short_name + @short_name
    else
      @application
    end
  end
end
