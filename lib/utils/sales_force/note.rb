module Utils
  module SalesForce
    class Note < Utils::SalesForce::Base
      attr_accessor :id, :created_date, :body, :title, :type, :api_object, :url
    end
  end
end
