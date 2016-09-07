module Utils
  module SalesForce
    class User < Utils::SalesForce::Base
      attr_accessor :id, :last_modified_by, :email, :first_name, :last_name, :record_type,  :type, :url,
        :api_object, :migration_complete, :modified, :created_date, :feed_itmes, :attachments, :notes

      def self.record_from_full_name(full_name)
        first_name, last_name = full_name.split(' ')
        Utils::SalesForce::Client.custom_query(
          query: "select id, createddate, email, firstname, lastname from user where firstName like '#{first_name}' and lastName like '#{last_name}'"
        )
      end
    end

  end
end
