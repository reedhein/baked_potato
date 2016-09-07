module Utils
  module SalesForce
    class BoxFrupC < Utils::SalesForce::Base
      attr_accessor :id, :box__folder_id__c, :box__record_id__c, :box__object_name__c, :type, :url
    end
  end
end
