module Utils
  module SalesForce
    class BoxFrupC < Utils::SalesForce::Base
      attr_accessor :id, :box__folder_id__c, :box__record_id__c, :box__object_name__c, :type, :url, :created_date
      def self.find_db_by_id(id)
        ::DB::SalesForceProgressRecord.first( box__record_id__c: id, object_type: 'box__FRUP__c' )
      end

      def opportunity_id
        opportunity__c
      end

      def self.create_from_objects(s_object, box_object, sf_client)
        sfid   = s_object.id
        box_id = box_object.id
        sf_client.create('box__FRUP__c', Box__Folder_ID__c: sfid, Box__Record_ID__c: box_id)
      rescue => e
        ap e.backtrace
        binding.pry
        puts e
      end
    end
  end
end
