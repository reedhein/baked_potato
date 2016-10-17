require 'sinatra'
require 'rb-readline'
require 'pry'
require 'awesome_print'
require 'classifier-reborn'
require_relative './lib/utils'
require 'sass'
require 'sass/plugin/rack'
require 'omniauth-salesforce'
require 'sinatra/partial'
Utils.environment = :sandbox
class BakedPotato < Sinatra::Base
  set env: :development
  set port: 4545
  set :bind, '0.0.0.0'
  configure do
    register Sinatra::Partial
    set :salesforce_partial, :erb
  end
  use Rack::Session::Pool
  use OmniAuth::Builder do
    provider :salesforce, CredService.creds.salesforce.production.api_key, CredService.creds.salesforce.production.api_secret, provider_ignores_state: true
    provider OmniAuth::Strategies::SalesforceSandbox, CredService.creds.salesforce.sandbox.kitten_clicker.api_key, CredService.creds.salesforce.sandbox.kitten_clicker.api_secret, provider_ignores_state: true
  end
  @box_client = Utils::Box::Client.instance
  @sf_client  = Utils::SalesForce::Client.instance

  image_path = Pathname.new('./public') + Date.today.to_s
  FileUtils.ln_s( CacheFolder.path, image_path ) unless image_path.exist?

  get '/' do
    if session[:salesforcesandbox].nil? || session[:box].nil? 
      redirect '/login'
      return
    end
    if session[:box][:email].split('@').last != 'reedhein.com'
      session.clear
      redirect '/login'
      return
    end
    begin
      @image       = BPImage.random_unlocked
      @image.lock
    rescue DataObjects::ConnectionError
      puts 'db error'
      sleep 0.1
      retry
    end
    @full_path   = get_full_path
    @name        = @image.path.basename.to_s
    @cases       = @image.cases
    @opportunity = @image.opportunity
    haml :index
  end

  get '/login' do
    haml :login
  end

  post '/categorize' do 
    # @image = BPImage.find(params[:full_path])
    redirect '/'
  end

  post '/authenticate/:provider' do
    case params[:provider].downcase 
    when 'salesforce'
      auth_params = {
        :display => 'page',
        :immediate => 'false',
        :scope => 'full refresh_token',
      }
      auth_params = URI.escape(auth_params.collect{|k,v| "#{k}=#{v}"}.join('&'))
      redirect "/auth/salesforce?#{auth_params}"
    when 'box'
      oauth_url = Boxr::oauth_url(
        URI.encode_www_form_component(CredService.creds.box.kitten_clicker.token),
        client_id: CredService.creds.box.kitten_clicker.client_id
      )
      redirect oauth_url
    when 'sandbox'
      auth_params = {
        display:     'page',
        immediate:   'false',
        scope:       'full',
      }
      auth_params = URI.escape(auth_params.collect{|k,v| "#{k}=#{v}"}.join('&'))
      redirect "/auth/salesforcesandbox?#{auth_params}"
    end
  end

  post '/edit_file_name' do
    email = session[:box][:email]
    Action::FileRename.new(email, params[:value], params[:pk]).peform
  end

  get '/unauthenticate' do
    # request.env['rack.session'] = {}
    session.clear
    redirect '/'
  end

  get '/auth/:provider/callback' do
    case params[:provider]
    when 'salesforce'
      save_salesforce_credentials('salesforce')
    when 'salesforcesandbox'
      save_salesforce_credentials('salesforcesandbox')
    when 'box'
      # creds = Boxr::get_tokens(params['code'])
      creds = Boxr::get_tokens(code=params[:code], client_id: CredService.creds.box.kitten_clicker.client_id, client_secret: CredService.creds.box.kitten_clicker.client_secret)
      client = create_box_client_from_creds(creds)
      user = populate_box_creds_to_db(client)
      session[:box] = {}
      session[:box][:email] = user.email
      redirect '/'
    else
      binding.pry
    end
    redirect '/'
  end

  post 'move_file' do
    email = session[:box][:email]
    Action::FileMove.new(email: email, source_id: params[:source_id], destination_id: params[:destination_folder_id]).perform
  end

  get '/salesforce/:id' do

  end

  get '/file/:id' do
    @image       = BPImage.find_by_id(params[:id])
    @image.lock
    {
      image_path: get_full_path,
      name: @image.path.basename.to_s,
      location: @image.cloud_path,
      id: @image.id
    }.to_json
  end

  def get_full_path
    path_array = @image.path.parent.to_s.split('/')[5..-1] << @image.path.basename.to_s
    path_array.join('/')
  end

  helpers do
    def iconify(file)
      case file.path.extname.downcase
        when '.pdf'
          'fa-file-pdf-o'
        when '.png', '.tif', '.jpeg', '.jpg'
          'fa-file-image-o'
        when '.xlsx'
          'fa-table'
        when '.docx', '.rtf', '.msg'
          'fa-windows'
        when '.gdoc', '.gsheet'
          'fa-google'
        when '.ini' , '.txt', '.doc'
          'fa-file-text-o'
        when '.url'
          'fa-link'
        when '.lnk'
          'fa-external-link'
        when '.htm', '.html'
          'fa-code'
        when '.db'
          'fa-databas'
        when '.zip'
          'fa-file-archive-o'
        else
          'fa-file'
      end
    end
  end

  private

  def save_salesforce_credentials(callback)
    user = DB::User.first_or_create(email: env.dig('omniauth.auth', 'extra', 'email'))
    binding.pry unless user
    begin
      if callback == 'salesforce'
        user.salesforce_auth_token     = env['omniauth.auth']['credentials']['token']
        user.salesforce_refresh_token  = env['omniauth.auth']['credentials']['refresh_token']
        session[:salesforce] = {}
        session[:salesforce][:email] = user.email
      elsif callback == 'salesforcesandbox'
        user.salesforce_sandbox_auth_token     = env['omniauth.auth']['credentials']['token']
        user.salesforce_sandbox_refresh_token  = env['omniauth.auth']['credentials']['refresh_token']
        session[:salesforcesandbox] = {}
        session[:salesforcesandbox][:email] = user.email
      else
        fail "don't know how to handle this environment"
      end
    rescue => e
      puts e.backtrace
      binding.pry
    end
    user.save
  end

  def populate_box_creds_to_db(client)
    email = client.current_user.login
    user  = DB::User.first_or_create(email: email)
    user.box_access_token   = client.access_token
    user.box_refresh_token  = client.refresh_token
    session[:box] = {}
    session[:box][:email] = email
    user.save
    user
  end

  def create_box_client_from_creds(creds)
    client = Boxr::Client.new(creds.fetch('access_token'),
              refresh_token: creds.fetch('refresh_token'),
              client_id:     CredService.creds.box.kitten_clicker.client_id,
              client_secret: CredService.creds.box.kitten_clicker.client_secret
            )
    client
  end

  run! if app_file == $0

end

