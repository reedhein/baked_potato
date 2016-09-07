module Utils
  module SalesForce
    class Attachment < Utils::SalesForce::Base
      attr_accessor :id, :zoho_id__c, :name, :type, :api_object, :url, :created_by_id, :description
    end
  end
end

