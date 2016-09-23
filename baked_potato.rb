require 'sinatra'
require 'pry'
require 'awesome_print'
require 'classifier-reborn'
require_relative './lib/utils'
require 'sass'
require 'sass/plugin/rack'
class BakedPotato < Sinatra::Base
  set env: :development
  set port: 4545
  set :bind, '0.0.0.0'
  @box_client = Utils::Box::Client.instance
  @sf_client  = Utils::SalesForce::Client.instance

  image_path = Pathname.new('./public') + Date.today.to_s
  FileUtils.ln_s( CacheFolder.path, image_path ) unless image_path.exist?

  get '/' do
    @image       = BPImage.random_unlocked
    @image.lock
    @full_path   = get_full_path
    @name        = @image.path.basename
    @cases       = @image.cases
    @opportunity = @image.opportunity
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


  def get_full_path
    path_array = @image.path.parent.to_s.split('/')[5..-1] << @image.path.basename.to_s
    path_array.join('/')
  end

  run! if app_file == $0
end


