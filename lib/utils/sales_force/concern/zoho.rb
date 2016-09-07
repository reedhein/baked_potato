module Utils
  module SalesForce
    module Concern
      module Zoho
        def zoho_attach(zoho_sushi, file_data)
          # description = description_from_file_data(file_data)
          begin
            file = Utils::Zoho::Base.client.download_file(zoho_sushi.module_name, file_data.id)
            return if file.nil?
            if file.is_a?(HTTParty::Response) && file.dig('response', 'error', 'code') == '4421'
              hold_process until past_midnight?
            end
            Utils::SalesForce::Client.instance.create('Attachment',
                                              Body: Base64::encode64(file),
                                              Description: "imported from zoho ID: #{zoho_sushi.id}",
                                              Name: file_data.file_name,
                                              ParentId: id)
            @modified = true
          rescue Errno::ETIMEDOUT, Net::OpenTimeout
            puts 'api timeout waiting 5 seconds and retrying'
            sleep 5
            retry
          rescue => e
            puts e
            binding.pry
          end
        end

        def find_zoho
          @zoho ||= Utils::Zoho::Base.counterpart(zoho_id__c)
        end

        private

      end
    end
  end
end
