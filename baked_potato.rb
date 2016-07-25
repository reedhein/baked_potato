require 'sinatra'
require 'pry'
require 'awesome_print'
require_relative '../global_utils/global_utils'
class BakedPotato < Sinatra::Base
  set env: :development
  set port: 4545
  set :bind, '0.0.0.0'
  @box_client = Utils::Box::Client.instance
  @sf_client  = Utils::SalesForce::Client.instance
  get '/' do
    haml :index
  end

  get '/:opportunity_id' do
    query = "SELECT Id, (SELECT Id, Name FROM Attachments), FROM Opportunity WHERE Id = #{:opportunity_id} LIMIT 1"
    @opp = @sf_client.custom_query(query: query)
  end

  run! if app_file == $0
end
