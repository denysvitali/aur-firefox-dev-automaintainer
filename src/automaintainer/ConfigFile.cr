require "yaml"
module Automaintainer
  class ConfigFile
    YAML.mapping(
      version: String,
      buildId: String
    )

    def initialize()
      @version = ""
      @buildId = ""
    end
  end
end
