module Utils
  module SalesForce
    class Opportunity < Utils::SalesForce::Base
      FIELDS =  %w[id amount description lead_source name probability stage_name type zoho_id__c created_date]
      attr_accessor :id, :zoho_id__c, :account, :amount, :close_date, :contract, :description, :expected_revenue, :forcase_category_name,
        :last_modified_by, :lead_source, :next_step, :name, :owner, :record_type, :partner_account, :pricebook_2,
        :campain, :is_private, :probability, :total_opportunity_quality, :stage_name, :synced_quote, :type, :url,
        :api_object, :migration_complete, :attachment_names, :modified, :created_date, :notes, :attachments, :chatters
      def contacts
        query = <<-EOF
          SELECT id, email, createddate, zoho_id__c,
          (SELECT id, createddate, body, title from notes),
          (SELECT id, Name FROM Attachments),
          (SELECT id, createddate, CreatedById, type, body, title FROM feeds)
          FROM contact
          WHERE accountid
          IN (SELECT accountid FROM opportunity WHERE id = '#{id}')
        EOF
        @contacts ||= @client.custom_query(
          query: query
        )
      end

      def account
        query = <<-EOF
          SELECT id, createddate, zoho_id__c, subject,
          (SELECT id, createddate, body, title from notes),
          (SELECT id, Name FROM Attachments),
          (SELECT id, createddate, CreatedById, type, body, title FROM feeds)
          FROM account
          WHERE id
          IN (SELECT accountid FROM opportunity WHERE id = '#{id}')
        EOF
        @account ||= @client.custom_query(
          query: query
        ).first
      end

      def cases
        query = <<-EOF
        SELECT id, createddate, closeddate, zoho_id__c, createdbyid, contactid, opportunity__c,
        (SELECT id, Name FROM Attachments),
        (SELECT id, createddate, CreatedById, type, body, title FROM feeds)
        FROM case
        WHERE opportunity__c = '#{id}'
        EOF
        @cases ||= @client.custom_query(
          query: query
        )
      end

      def cases=(cases)
        @cases = cases
      end

    end
  end
end
