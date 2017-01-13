module Utils
  module SalesForce
    class Case < Utils::SalesForce::Base
      attr_accessor :id, :zoho_id__c, :last_modified_by, :name,  :record_type,
        :type, :url, :api_object, :migration_complete, :attachment_names, :modified, :time_share_name__c,
        :created_date, :closed_date, :contact_id, :created_by_id, :case_id_18__c, :status, :is_closed,
        :exit_completed_date__c, :case_id__c, :notes, :attachments, :chatters, :description, :feeds, :subject, :case_number, :opportunity__c,
        :exit_complete_docs_folder__r, :ts_docs_folder__r
      

      FIELDS =  %w[id description zoho_id__c created_date type]
      def opportunity
        @opportunity ||= @sf_client.custom_query( query: construct_opp_query( opportunity__c ) ).first
      end

      def opportunity_id
        opportunity__c
      end

      def attachments
        super
      end

      def construct_opp_query( id )
        <<-EOF
          SELECT Name, Id, createdDate,
          (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, opportunity__c, subject FROM cases__r),
          (SELECT Id, Name FROM Attachments)
          FROM Opportunity
          WHERE id = '#{id}'
        EOF
      end
    end
  end
end
