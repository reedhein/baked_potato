module Utils
  module Box
    class Client 
      include Inspector
      require_relative './concern/db'
      include Utils::Box::Concern::DB #feels weird that this is required

      attr_reader :client

      def initialize(user = DB::User.Doug)
        @client = self.class.client(user)
        dynanmic_methods_for_client #dynamic methods that passes methods to @client
      end

      def folders
        root_folder_items
      end

      def opportunities
        folder("5665505677")
      end

      def cases
        folder("5665821837")
      end

      def self.client(user = DB::User.Doug)
        token_refesh_callback = lambda do |access, refresh, identifier|
          user.box_access_token  = access
          user.box_refresh_token = refresh
          user.box_identifier    = identifier
          user.save
          puts "Box Token updated: #{Time.now.to_s}"
        end
        token = user.box_access_token || CredService.creds.box.utility_app.token
        ::Boxr::Client.new(token,
            refresh_token:  user.box_refresh_token,
            identifier:     user.box_identifier,
            client_id:     CredService.creds.box.utility_app.client_id,
            client_secret: CredService.creds.box.utility_app.client_secret,
            &token_refesh_callback
          )
      end

      private

      def dynanmic_methods_for_client
        methods = @client.public_methods - self.public_methods
        methods.each do |meth|
          define_singleton_method meth do |*args|
            begin
              return_value = @client.send(meth, *args)
              if return_value.is_a? BoxrMash
                convert_api_object_to_local_storage(return_value)
              else
                return_value
              end
            rescue Boxr::BoxrError => e
              if e.to_s.match(/(Item is trashed|Not Found)/)
                return nil
              else
                retry_count ||= 0
                @client = self.class.client(DB::User.Doug)
                if retry_count <= 3
                  retry_count += 1
                  retry
                else
                  ap e.backtrace
                  puts e
                  binding.pry
                end
              end
            end
          end
        end
      end
    end
  end
end
