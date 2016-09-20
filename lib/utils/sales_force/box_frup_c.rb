module Utils
  module SalesForce
    class BoxFrupC < Utils::SalesForce::Base
      attr_accessor :id, :box__folder_id__c, :box__record_id__c, :box__object_name__c, :type, :url
      def self.find_db_by_id(id)
        ::DB::SalesForceProgressRecord.first( box__record_id__c: id, object_type: 'box__FRUP__c' )
      end

      def opportunity_id
        opportunity__c
      end
    end
  end
end
