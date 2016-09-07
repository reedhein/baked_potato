module Utils
  module SalesForce
    class Account < Utils::SalesForce::Base
      attr_accessor :id, :zoho_id__c, :last_modified_by,  :name,  :record_type,  :type, :url,
        :api_object, :migration_complete, :attachment_names, :modified, :created_date
      def contacts
        @client.custom_query(
          query: "select id, email, createddate from contact where accountid = '#{id}'"
        )
      end
    end
  end
end
