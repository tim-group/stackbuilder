      module Extensions
        def provision_vms(specs)
          mc = new_client("provisionvm")
          return mc.provision_vms(:specs=>specs)
        end

        def ping()
          client = ::MCollective::Client.new(@options[:config])
          client.options = @options
          responses = []
          client.req("ping", "discovery") do |resp|
            responses << resp[:senderid]
          end
          return responses
        end

        def wait_for_ping(nodes)
          found = false
          result = nil
          retries = 60

          pp nodes

          retries.times do |i|
            result = ping()
            pp result
            if nodes.to_set.subset?(result.to_set)
              found = true
              break
            end
          end
          raise "timeout out waiting for hosts to be available" unless found
          return result
        end

        def run_nrpe(nodes=nil)
          mc = new_client("nrpe", :nodes=>nodes)
          mc.runallcommands.each do |resp|
            nrpe_results[resp[:sender]] = resp
          end
        end

        def puppetd(nodes=nil)
          mc = new_client("puppetd", nodes=> nodes)

          pp mc.status()
        end

        def puppetroll(nodes=nil)
          mc = new_client("puppetd", nodes=> nodes)
          engine = PuppetRoll::Engine.new({:concurrency=>5}, [], nodes, PuppetRoll::Client.new(nodes, mc))
          engine.execute()
          return engine.get_report()
        end

        def puppetca_sign(hostname)
          mc = new_client("puppetca")
          return mc.sign(:certname => hostname)[0]
        end


      end


