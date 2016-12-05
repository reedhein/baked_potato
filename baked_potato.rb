require 'sinatra'
require 'rb-readline' if RbConfig::CONFIG['host_os'] =~ /darwin/
require 'pry'
require 'awesome_print'
require 'classifier-reborn'
require_relative './lib/utils'
require 'sass'
require 'sass/plugin/rack'
require 'omniauth-salesforce'
require 'sinatra/partial'
#TODO 
# skinny stacked css
# trash button fixed ✅
# test refresh ✅
# create source redirect login logic ✅
# test moves
# test move on UI
# create parent folder logic
# add scrub message
# add user attribution

Utils.environment = :sandbox
class BakedPotato < Sinatra::Base
  set env: :development
  set port: 4545
  set :bind, '0.0.0.0'
  set :public_folder, 'public'
  use Rack::Session::Cookie, :key => 'rack.session', :path => '/', :secret => 'your_secret', session_secret: 'supersecret'
  configure do
    register Sinatra::Partial
    set :salesforce_partial, :erb
  end
  use Rack::Session::Pool
  use OmniAuth::Builder do
    provider :salesforce,
      CredService.creds.salesforce.production.kitten_clicker_prod.api_key,
      CredService.creds.salesforce.production.kitten_clicker_prod.api_secret,
      provider_ignores_state: true
    provider OmniAuth::Strategies::SalesforceSandbox,
      CredService.creds.salesforce.production.kitten_clicker_prod.api_key,
      CredService.creds.salesforce.production.kitten_clicker_prod.api_secret,
      provider_ignores_state: true
  end
  @box_client = Utils::Box::Client.new
  @sf_client  = Utils::SalesForce::Client.new

  image_path = Pathname.new(Dir.pwd + '/public') + Date.today.to_s
  smb_path = Pathname.new(Dir.pwd + '/public/smb_cache')
  FileUtils.ln_s( CacheFolder.path, image_path ) unless image_path.exist? || image_path.symlink?
  FileUtils.ln_s( CacheFolder.smb_path, smb_path ) unless smb_path.exist? || smb_path.symlink?

  get '/' do
    if session[:email].nil?
      return_address = env['HTTP_HOST']
      return_port    = env['SERVER_PORT']
      escaped_address = URI.escape(return_address)
      puts 'redirecting'
      redirect "https://teamkatlas.com?return_address=#{escaped_address}&return_port=#{return_port}"
      return
    end
    opp_id = CacheFolder.path.children.select{|e| e.directory?}.sample.basename.to_s
    redirect "/salesforce/#{opp_id}"
  end

  get '/frup_fixer' do
    haml :frup_fixer
  end

  post '/frup_fixer' do 
    cm = CloudMigrator.new( user: DB::User.first(email: session[:email]) )
    cm.frup_fixer(params[:sobject_id])
    redirect "http://na34.salesforce.com/salesforce/#{params[:sobect_id]}"
  end

  get '/authorize' do
    user = DB::User.first_or_create(email: params[:email])
    user.update(
      salesforce_auth_token:    params[:salesforce_auth_token],
      salesforce_refresh_token: params[:salesforce_refresh_token],
      box_auth_token:           params[:box_auth_token],
      box_refresh_token:        params[:box_refresh_token]
    )
    self.session ||= {}
    self.session[:email] = user.email
    redirect '/'
  end

  get '/refresh/:id' do
    cm = CloudMigrator.new(user: DB::User.first(email: session[:email]))
    cm.produce_single_snapshot_from_scratch(params[:id])
    return {finished: true}.to_json
  end

  get '/s_drive/file/:sha1' do
    record = DB::SMBRecord.first(sha1: params['sha1'])
    return record.to_json
  end

  get '/s_drive/:terms' do
    records = search_s_drive_from_sting(params[:terms])
    organize_records(records).to_json
  end

  get '/login' do
    haml :login
  end

  post '/categorize' do 
    # @image = BPImage.find(params[:full_path])
    redirect '/'
  end

  get '/salesforce/:id' do 
    if session[:email].nil?
      redirect 'https://teamkatlas.com/'
    end
    begin
      record = DB::SalesForceProgressRecord.first(sales_force_id: params[:id])
      if record.nil?
        CloudMigrator.new(user: DB::User.first(email: session[:email])).produce_single_snapshot_from_scratch(params[:id])
        record = DB::SalesForceProgressRecord.first(sales_force_id: params[:id])
      end
      if record.object_type == :opportunity || record.object_type.downcase == 'opportunity'
        @opportunity  = CacheFolder.find_from_record(record)
      else
        sf_case = CacheFolder.find_from_record(record)
        @opportunity = sf_case.opportunity
      end
      audit_opportunity
      @cases = @opportunity.cases
      haml :index
    rescue Restforce::UnauthorizedError
      redirect 'https://teamkatlas.com/unauthenticate'
    rescue  => e
      ap e.backtrace
      binding.pry
      puts e
    end
  end

  post '/authenticate/:provider' do
    puts 'yippy'
    case params[:provider].downcase 
    when 'salesforce'
      auth_params = {
        :display => 'page',
        :immediate => 'false',
        :scope => 'full',
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
    email = session[:email]
    Action::FileRename.new(email: email, rename: params[:value], file_id: params[:pk], s_drive: params[:s_drive]).peform
  end

  get '/logout' do
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
      creds  = Boxr::get_tokens(params[:code], client_id: CredService.creds.box.kitten_clicker.client_id, client_secret: CredService.creds.box.kitten_clicker.client_secret)
      client = create_box_client_from_creds(creds)
      user   = populate_box_creds_to_db(client)
      session[:box]         = {}
      session[:box][:email] = user.email
      redirect '/'
    else
      binding.pry
    end
    redirect '/'
  end

  post '/move_file' do
    begin
      email = session[:email]
      updated_record = Action::FileMove.new(email: email,
                          file_id: params[:file_id],
                          source_id: params[:source_id],
                          destination_id: params[:destination_id]
                        ).perform
      {status: 'success', destination_id: params[:destination_id], file_id: updated_record.file_id, original_id: params[:file_id]}.to_json
    rescue => e
      ap e.backtrace
      binding.pry
      puts 'lol'
    end
  end

  post '/delete_file' do 
    begin
      binding.pry
      email = session[:email]
      Action::FileDelete.new(email: email, file_id: params[:file_id]).perform
      {status: 'success', file_id: params[:file_id]}.to_json
    rescue => e
      ap e.backtrace
      puts e
      binding.pry
    end
  end
  
  get '/salesforce/:id' do
    binding.pry
    type = CacheFolder.folder_type_by_id(params[:id])
    if type == :opportunity
      @opportunity = CacheFolder.find_by_id(params[:id])
    elsif type == :case
      @case = CacheFolder.find_by_id(params[:id])
    end
    @cases = @opportunity.cases
  end

  get '/file/:id' do
    begin
      @image       = BPImage.find_by_id(params[:id])
      {
        image_path: get_full_path,
        name: @image.db.filename,
        location: @image.cloud_path,
        id: @image.id
      }.to_json
    rescue DataObjects::ConnectionError => e
      puts e
      sleep 0.05
      retry
    end
  end

  get '/s_drive/screenable/:path' do
    binding.pry
  end

  def get_full_path
    path_array = @image.path.parent.to_s.split('/')[5..-1] << @image.path.basename.to_s
    '/' + path_array.join('/')
  rescue => e
    ap e.backtrace[0..5]
    binding.pry
    puts e
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

  before '/*' do 
    @user_email = session[:email]
  end

  private

  def audit_opportunity
    if @opportunity.meta[:name].blank? ||
        @opportunity.cases.detect{ |c| c.meta[:name].nil? && c.meta[:subject].nil? } ||
          @opportunity.box_folders.detect{ |bf| bf.meta.nil? || bf.meta[:name].nil? }
      puts 'need to spot check'
      cm = CloudMigrator.new
      cm.produce_single_snapshot_from_scratch(params[:id])
    end
  end

  def search_s_drive_from_sting(string)
    search_terms = string.squish.scan(/\w+/)
    records = []
    search_terms.each do |term|
      next if term.downcase == 'household' || term.downcase == 'and' || term.size <= 3
      results = DB::SMBRecord.all(:relative_path.like => "%#{term}%")
      records << results unless results.empty?
    end
    records.flatten.uniq
  end

  def organize_records(records)
    result = {}
    ['2012', '2013', '2014', '2015', '2016', '2017'].each do |date|
      result[date] = []
    end
    records.each do |r|
      next unless result[r.year]
      result[r.year] << r
    end
    result
  rescue => e
    puts e
    binding.pry
  end

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
  def authenticate_me(user)
    session[:box] = {}
    session[:box][:email] = 'doug@reedhein.com'
    session[:salesforce] = {}
    session[:salesforce][:email] = 'doug@reedhein.com'
  end
  run! if app_file == $0

end

