module Utils
  module SalesForce
    class Case < Utils::SalesForce::Base
      attr_accessor :id, :zoho_id__c, :last_modified_by, :name,  :record_type,
        :type, :url, :api_object, :migration_complete, :attachment_names, :modified,
        :created_date, :closed_date, :contact_id, :created_by_id, :case_id_18__c, :status, :is_closed,
        :exit_completed_date__c, :case_id__c, :notes, :attachments, :chatters, :description, :feeds, :subject, :case_number, :opportunity__c

      FIELDS =  %w[id description zoho_id__c created_date type]
      def opportunity
        @opportunity ||= @client.custom_query(
          query: "SELECT id, createddate, closedate, zoho_id__c FROM opportunity WHERE id in (select opportunity__c from case where id = '#{@id}')"
        ).first
      end

      def opportunity_id
        opportunity__c
      end

      def attachments
        super
      end
    end
  end
end
