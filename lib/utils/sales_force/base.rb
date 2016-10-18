module Utils
  module SalesForce
    class Base
      require_relative './concern'
      include Utils::SalesForce::Concern::DB #feels weird that this is required
      include Utils::SalesForce::Concern::Zoho
      include Utils::SalesForce::Concern::Box
      # include Inspector
      attr_reader :client, :zoho, :api_object
      def initialize(api_object)
        @client             = Utils::SalesForce::Client.new
        @api_object         = api_object
        @storage_object     = convert_api_object_to_local_storage(api_object)
        @problems           = []
        map_attributes(api_object)
      end

      def delete
        @client.destroy(type, id)
      end

      def attachments
        @attachments ||= @client.custom_query(
          query: "SELECT Id, Name, Body FROM Attachment WHERE ParentId = '#{id}'"
        )
      end

      def notes
        @notes ||= @client.custom_query(
          query: "select id, createddate, body, title from note where parentid = '#{id}'"
        )
      end

      def chatters
        @chatters ||= @client.custom_query(
          query: "select id, createddate, CreatedById, type, body, title, parentid from feeditem where parentid = '#{id}'"
        )
      end

      def update(change_hash)
        change_hash.merge!(Id: self.id)
        @client.update(self.type, change_hash)
      end

      def migration_complete?(task) #attachment or notes
        @storage_object.send(task.to_s + '_migration_complete')
      end

      def mark_completed(task)
        @storage_object.send(task.to_s + '_migration_complete=', true)
        @storage_object.save
      end

      private

      def map_attributes(params)
        params.each do |key, value|
          next if key == "attributes"
          next if key.downcase == "body" && params.dig('attributes', 'type') == 'Attachment'#prevent attachment from being downloaded if we haven't checked fro presence
          if key =~/__r$/ 
            key = key.gsub(/__r$/, '')
          end
          if !value.nil? && value.respond_to?(:entries)
            value = value.entries.map do |entity|
              klass = ['Utils', 'SalesForce', entity.attributes.type].join('::').classify.constantize
              klass.new(entity)
            end
          end
          self.send("#{key.underscore}=", value)
        end
        params.fetch('attributes').each do |key, value|
          self.send("#{key.underscore}=", value)
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
