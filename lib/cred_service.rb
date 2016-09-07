require 'deepstruct'
class CredService
  def self.creds
    yml = YAML::load_file(File.join(__dir__, '..', 'secrets.yml'))
    DeepStruct.wrap(yml)
  end

  def initialize
    yml = YAML::load_file(File.join(__dir__, '..', 'secrets.yml'))
    DeepStruct.wrap(yml)
  end

end
