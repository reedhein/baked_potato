module Utils
  module SalesForce
    class Determine
      include Utils
      attr_accessor :potentials, :contacts, :leads, :accounts, :email, :name, :phone, :sf_client, :sf_object
      def initialize(sf)
        @sf_object = sf
        @sf_client = sf.client
        @potentials, @contacts, @leads, @accounts = [], [], [], []
        @email, @name, @phone  = get_meta
      end

      def detect_zoho
        %w[potential contact lead account].detect do |zoho_object|
          zoho_object_fields(zoho_object).detect do |method_name| # i removed compact
            zoho_api_lookup_results = ['RubyZoho' , 'Crm', zoho_object.camelize].join('::').constantize.send("find_by_#{method_name.to_s}", self.send(method_name)) || []
            [zoho_api_lookup_results].flatten.each do |result|
              populate_results(result)
            end
          end
        end
      end

      def find_zoho
        fetch_zoho_objects(@sf_object)
        self
      end

      private

      def fetch_zoho_objects(sf)
        %w[lead account contact potential].each do |zoho_object|
          puts "checking API against zoho object: #{zoho_object}"
          sleep 9
          begin
            zoho_object_fields(zoho_object).compact.each do |method_name|
              sleep 9
              search_value = self.send(method_name)
              next if search_value.nil?
              puts "searching #{method_name} on #{zoho_object}"
              zoho_api_lookup_results = ['RubyZoho' , 'Crm', zoho_object.camelize].join('::').constantize.send("find_by_#{method_name.to_s}", search_value) || []
              [zoho_api_lookup_results].flatten.each do |result|
                puts "found #{result}"
                populate_results(result)
                return self
              end
            end
          rescue Net::OpenTimeout
            puts "network timeout sleeping 5 seconds then trying again"
            sleep 5
            retry
          rescue => e
            if e.to_s =~ /4820/
              hold_process until past_midnight? || fifteen_minute_interlude?
              retry
            end
          rescue => e
            ap e.backtrace
            binding.pry
          end
        end
        self
      end

      def get_meta
        case @sf_object.type
        when 'Contact'
          return_value = @sf_client.query("SELECT email, name, phone FROM contact WHERE id = '#{@sf_object.id}'")
        when 'Opportunity'
          return_value = @sf_client.query("SELECT email, name, phone FROM contact WHERE accountid IN (SELECT accountid FROM Opportunity WHERE id = '#{@sf_object.id}')")
        when 'Account'
          return_value = @sf_client.query("SELECT email, name, phone FROM contact WHERE accountid = '#{@sf_object.id}'")
        when 'Case'
          return_value = @sf_client.query("select email, name, phone from contact  where id in (select contactid from case where id = '#{@sf_object.id}')")
        end
        first_entry  = return_value.first || {}
        [first_entry.fetch('Email', nil), first_entry.fetch('Name', nil), first_entry.fetch('Phone', nil)]
      end

      def populate_results(zoho_api_lookup_result)
        global_zoho = ['Utils', 'Zoho', zoho_api_lookup_result.module_name.singularize].join('::').constantize.new(zoho_api_lookup_result)
        bucket_for_related_objects = self.send(zoho_api_lookup_result.module_name.downcase)
        bucket_for_related_objects << global_zoho unless bucket_for_related_objects.map(&:id).include? global_zoho.id
      end

      def zoho_object_fields(zoho_object)
        #return values that we can query against
        ['RubyZoho','Crm', zoho_object.camelize].join('::').constantize.new.fields & [:email, :phone, :name]
      end
    end
  end
end
