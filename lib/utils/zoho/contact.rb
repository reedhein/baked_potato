module Utils
  module Zoho
    class Contact < Utils::Zoho::Base
      include Utils::Zoho::Concern::Notes
    end
  end
end
