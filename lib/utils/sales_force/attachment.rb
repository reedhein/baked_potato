module Utils
  module SalesForce
    class Attachment < Utils::SalesForce::Base
      attr_accessor :id, :zoho_id__c, :name, :type, :api_object, :url, :created_by_id, :description
      def rename(rename)
        update('Attachment', Id: @id, Name: rename)
      end
    end
  end
end

