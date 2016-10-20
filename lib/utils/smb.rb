class SMB
  require 'sambal'
  include Singleton
  def initialize
    host     = CredService.creds.smb.host
    user     = CredService.creds.smb.user
    password = CredService.creds.smb.password
    binding.pry
    Sambal::Client.new(host: host, user: user, password: password, share:'DATA')
  end

end
