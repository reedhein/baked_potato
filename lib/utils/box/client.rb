module Utils
  module Box
    class Client
      include Inspector
      include Singleton
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

      def create_folders(desired_folder_names) #depricated in favor for SFDC trigger
        desired_folder_names.each_with_index do |folder, i|
          parent_folder = desired_folder_names[0..i].join('/')
          begin
            @client.folder(parent_folder)
          rescue Boxr::BoxError => e # the box folder could not be found
            @client.create_folder(folder, parent_folder) if e.to_s =~ /Not Found/
          end
        end
      end

      def self.client(user = DB::User.Doug)
        token_refesh_callback = lambda do |access, refresh, identifier| 
          user.box_access_token  = access
          user.box_refresh_token = refresh
          user.box_identifier    = identifier
          user.save
          puts "Box Token updated: #{Time.now.to_s}"
        end
        token = user.box_access_token || CredService.creds.box.token
        ::Boxr::Client.new(token,
            refresh_token:  user.box_refresh_token,
            identifier:     user.box_identifier,
            client_id:     CredService.creds.box.client_id,
            client_secret: CredService.creds.box.client_secret,
            &token_refesh_callback
          )
      end

      private

      def dynanmic_methods_for_client
        methods = @client.public_methods - self.public_methods
        methods.each do |meth|
          define_singleton_method meth do |*args|
            @client.send(meth, *args)
          end
        end
      end
    end
  end
end
