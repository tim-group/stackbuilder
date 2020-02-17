module MCollective
  class Discovery
    class Mongorest
      require 'json'
      require 'net/http'
      require 'set'

      class << self
        def discover(filter, timeout, limit = 0, client = nil)
          config = Config.instance

          mongohost = config.pluginconf["discovery.mongorest.host"] || "puppet"
          mongoport = config.pluginconf['discovery.mongorest.port'] || '28017'
          mongodb = config.pluginconf["discovery.mongorest.db"] || "puppet"
          collection = config.pluginconf["discovery.mongorest.collection"] || "nodes"
          newerthan = Time.now.to_i - Integer(config.pluginconf["discovery.mongorest.criticalage"] || 3600)

          uri = "http://#{mongohost}:#{mongoport}/#{mongodb}/#{collection}/?limit=10000"
          body = nil
          data = nil

          begin
            body = Net::HTTP.get(URI(uri))
            data = JSON.parse(body)
          rescue Exception => e
            raise("Could not get #{uri}, returned JSON #{body}, exception #{e}")
          end
          rows = data['rows']
          Log.debug("Got discovery reply from mongorest, total hosts #{rows.count}")
          rows.reject! { |row| !row['collectives'].to_set.include?(client.options[:collective]) }
          rows.reject! { |row| row['lastseen'] < newerthan }
          Log.debug("Filtered on collective and lastseen, total hosts #{rows.count}")

          filter.keys.each do |key|
            case key
            when "fact"
              rows = fact_search(filter["fact"], rows)

            when "cf_class"
              rows = search(filter["cf_class"], rows, 'classes')

            when "agent"
              rows = search(filter["agent"], rows, 'agentlist')

            when "identity"
              rows = search(filter["identity"], rows, 'fqdn')
            end
          end

          Log.debug("Filtered on facts/agent/identity/class, total hosts #{rows.count}")

          rows.map { |row| row['fqdn'] }
        end

        def fact_search(filter, collection)
          return collection if filter.empty?
          filter.each do |f|
            fact = f[:fact]
            value = regexy_string(f[:value])
            query = nil

            collection.reject! do |row|
              test = row['facts'][fact]
              if test.nil?
                true
              else
                !test.send(f[:operator].to_s, value)
              end
            end
          end
          collection
        end

        def search(filter, collection, field)
          return collection if filter.empty?
          filter.each do |f|
            collection.reject! do |row|
              !regexy_string_match(f, row[field])
            end
          end
          collection
        end

        def regexy_string_match(string, things)
          filter = regexy_string(string)
          if filter.is_a?(Regexp)
            things.grep(filter)
          else
            things.include?(filter)
          end
        end

        def regexy_string(string)
          if string.match("^/")
            Regexp.new(string.gsub("\/", ""))
          else
            string
          end
        end
      end
    end
  end
end
