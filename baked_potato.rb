require 'sinatra'
require 'pry'
require 'awesome_print'
require 'classifier-reborn'
require_relative '../global_utils/global_utils'
require_relative 'cache_folder'
class BakedPotato < Sinatra::Base
  set env: :development
  set port: 4545
  set :bind, '0.0.0.0'
  @cache_folder = '/Users/voodoologic/Sandbox/cache_folder'
  @box_client = Utils::Box::Client.instance
  @sf_client  = Utils::SalesForce::Client.instance
  get '/' do
    @image     = BPImage.random_unlocked
    @image.lock
    @full_path   = @image.full_path.split('/')[-2..-1].join('/')
    @name        = @image.full_path.split('/')[-1]
    @size        = @image.db_image.size
    @type        = @image.db_image.type
    @fingerprint = @image.db_image.fingerprint
    haml :index
  end

  post '/categorize' do 
    # @image = BPImage.find(params[:full_path])
    redirect '/'
  end

  get '/:opportunity_id' do
    # cf   = CacheFolder.new(opp_id: :opportunity_id)
    # @images = cf.images.each{|i| i.lock}
    # @opp = @sf_client.custom_query(query: query)
  end

  run! if app_file == $0
end


