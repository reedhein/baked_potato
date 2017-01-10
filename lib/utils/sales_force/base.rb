module Utils
  module SalesForce
    class Base
      require_relative './concern'
      include Utils::SalesForce::Concern::DB #feels weird that this is required
      include Utils::SalesForce::Concern::Zoho
      include Utils::SalesForce::Concern::Box
      # include Inspector
      attr_reader :client, :zoho, :api_object, :storage_object
      def initialize(api_object)
        @sf_client          = Utils::SalesForce::Client.new
        @api_object         = api_object
        @storage_object     = convert_api_object_to_local_storage(api_object)
        @problems           = []
        map_attributes(api_object)
      end

      def type
        @storage_object.object_type #clunky
      end

      def delete
        @sf_client.destroy(type, id)
      end

      def attachments
        @attachments ||= @sf_client.custom_query(
          query: "SELECT Id, Name, Body FROM Attachment WHERE ParentId = '#{id}'"
        )
      end

      def notes
        @notes ||= @sf_client.custom_query(
          query: "select id, createddate, body, title from note where parentid = '#{id}'"
        )
      end

      def chatters
        @chatters ||= @sf_client.custom_query(
          query: "select id, createddate, CreatedById, type, body, title, parentid from feeditem where parentid = '#{id}'"
        )
      end

      def update(change_hash)
        change_hash.merge!(Id: self.id)
        @sf_client.update(self.type, change_hash)
      end

      def migration_complete?(task) #attachment or notes
        @storage_object.send(task.to_s + '_migration_complete')
      end

      def mark_completed(task)
        @storage_object.send(task.to_s + '_migration_complete=', true)
        @storage_object.save
      end

      def box_folder(box_client)
        sf_linked = query_frup
        binding.pry
        parent_box_folder = box_client.folder_from_id( sf_linked.box__folder_id__c )
        @sf_client.custom_query(query: "SELECT id FROM RH_Doc_Folder")
      end

      private

      def query_frup
        @sf_client.custom_query(query:"SELECT id, createddate, box__Folder_ID__c, box__Object_Name__c, box__Record_ID__c FROM box__FRUP__c WHERE box__Record_ID__c = '#{self.id}' LIMIT 1")
      end

      def poll_for_frup
        kill_counter = 0
        sf_linked = query_frup(sobject)
        while sf_linked.nil? do
          # TODO the below line should work but it didin't
          # sobject.update({'Create_Box_Folder__c': true})
          # create_folder_through_browser(sobject)
          @browser_tool.visit_salesforce(sobject)
          puts 'sleeping until created'
          sleep 6
          kill_counter += 1
          break if kill_counter > 2
          sf_linked = query_frup(sobject)
        end
        if sf_linked
          sf_linked.first
        else
          document_offesive_object(sobject) 
          nil
        end
      rescue => e
        ap e.backtrace
        binding.pry
        puts 'pull_for_frup'
      end

      def map_attributes(params)
        params.each do |key, value|
          next if key == "attributes"
          next if key.downcase == "body" && params.dig('attributes', 'type') == 'Attachment'#prevent attachment from being downloaded if we haven't checked fro presence

          related_obj = nil
          root_obj    = nil

          if key =~ /__r$/
            my_key = key.gsub(/__r$/, '')
            my_params = params.clone
            my_params[my_key] = params[key]
            my_params.delete(key)
            klass = make_class(my_key)
            binding.pry
            if my_params[my_key].is_a? Restforce::Collection
              my_params[my_key].each do |api_object|
                klass = make_class(my_key)
                klass.new(api_object)
              end
            end
            related_obj = klass.new(my_params[my_key])
          end

          if !value.nil? && value.respond_to?(:entries) && related_obj.nil?
            value = value.entries.to_h.map do |entity|
              klass = ['Utils', 'SalesForce', entity.attributes.type].join('::').classify.constantize
              root_obj = klass.new(entity)
            end
          end
          if related_obj.present?
            method_name = related_obj.storage_object.object_type.downcase
            self.send(method_name + '=', related_obj) if  self.respond_to?(method_name)
          else
            self.send("#{key.underscore}=", value)
          end
        end
      end

      def make_class(key)
        case key
        when 'Exit_Complete_Docs_Folder'
          Utils::SalesForce::ExitCompleteDocFolderC
        when 'TS_Docs_Folder'
          Utils::SalesForce::TSDocFolderC
        when 'RH_Docs_Folder'
          Utils::SalesForce::RHDocFolderC
        else
          ['Utils', 'SalesForce', key].join('::').classify.constantize
        end
      end

      def wrap_sub_query_values(key, return_value)
        return [] if return_value.nil?
        case key
        when 'Feeds'
          klass = ['Utils', 'SalesForce', 'FeedItem'].join('::').classify.constantize
        else
          klass = ['Utils', 'SalesForce', key.camelize].join('::').classify.constantize
        end
        return_value.entries.map do |entity|
          klass.new(entity)
        end
      end
    end
  end
end
