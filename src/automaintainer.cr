require "./automaintainer/*"
require "http/client"
require "xml"
require "openssl"
require "openssl/lib_crypto"

module Automaintainer
  @@configFilePath = "./data/config.yaml"
  @@originalPKGBUILD = "~/ffdev-aur/PKGBUILD"
  @@makepkg = "/usr/local/bin/makepkg"
  @@startingBID = "20170613150320"
  @@startingVersion = "55.0a1"
  @@nextV = "https://aus5.mozilla.org/update/6/Firefox/%VERSION%/%BUILDID%/Linux_x86_64-gcc3/en-US/aurora/Linux/NA/default/default/update.xml?force=1"
  @@arch = ["i686", "x86_64"]
  @@debug = false

  def self.run
    config = loadConfig()

    if config
      version = config.version
      buildId = config.buildId
    else
      version = @@startingVersion
      buildId = @@startingBID
    end

    vurl = @@nextV.gsub(/%VERSION%/, version)
    vurl = vurl.gsub(/%BUILDID%/, buildId)

    response = HTTP::Client.get vurl
    document = XML.parse(response.body)
    update = document.first_element_child

    if update
      elements = update.children.select(&.element?)
      if elements.size > 0
        updEl = elements[0]
        if updEl["appVersion"] != version || updEl["buildID"] != buildId
          # New version
          updC = updEl.children.select(&.element?)
          node = updC[0]
          newVer = nil
          if node
            dlurl = URI.parse(node["URL"])
            query = dlurl.query
            if query
              query.split("&") do |val|
                arr = val.split("=")
                if arr[0] == "product"
                  dirtyVer = arr[1]
                  match = dirtyVer.match /devedition-(\d+\.\d+[a-z]\d+)-complete/
                  if match
                    newVer = match[1]
                  end
                end
              end
            end
          end

          if !newVer
            newVer = updEl["appVersion"]
          end

          puts "New version! #{newVer} - #{updEl["buildID"]}"
          self.updatePKGBUILD(newVer, updEl["buildID"])
          if config
            config.version = updEl["appVersion"]
            config.buildId = updEl["buildID"]
            self.writeConfig(config)
          end

          if updEl["appVersion"] =~ /^[A-Za-z\.0-9]+$/ && updEl["buildID"] =~/^[0-9]+$/
            stdout = IO::Memory.new
            stderr = IO::Memory.new

            result = Process.run(
              "cp PKGBUILD ~/ffdev-aur/ && cd ~/ffdev-aur/ && #{@@makepkg} --printsrcinfo > .SRCINFO && git add PKGBUILD .SRCINFO && git commit -m 'Bump to version #{newVer}, BID: #{updEl["buildID"]}' && git push origin master",
              nil, nil, false, true, false, stdout, stderr
            )
            puts "Output: #{stdout.to_s}"
            puts "Error: #{stderr.to_s}"
            puts "Success: #{result.success?}"
          else
            puts "Doesn't match"
          end
        end
      end
    end
  end

  def self.loadConfig : (ConfigFile | Nil)
    filePath = File.expand_path(@@configFilePath)
    fileDir = File.dirname(filePath)

    if !Dir.exists?(fileDir)
      Dir.mkdir_p(fileDir)
    end

    if !File.file?(@@configFilePath)
      cf = self.createConfig
      return cf
    end

    cf = nil
    begin
      cf = ConfigFile.from_yaml(File.read(filePath))
    rescue ex
      puts "Unable to parse config - replacing with a new one"
      cf = self.createConfig
    end
    return cf
  end

  def self.createConfig
    cf = ConfigFile.new
    cf.version = @@startingVersion
    cf.buildId = @@startingBID
    self.writeConfig(cf)
    return cf
  end

  def self.writeConfig(cf : ConfigFile)
    filePath = File.expand_path(@@configFilePath)
    File.write(filePath, cf.to_yaml)
  end

  def self.updatePKGBUILD(version, bid)
    pkgbuild = File.read(File.expand_path(@@originalPKGBUILD))
    if pkgbuild.size < 20
      puts "Too short!"
      exit
    end

    pkgbuild = pkgbuild.gsub(/^pkgver=(.*?)$/m, "pkgver=#{version}_#{bid}")
    pkgbuild = pkgbuild.gsub(/^_ffver=(.*?)$/m, "_ffver=#{version}")
    pkgbuild = pkgbuild.gsub(/^_ffbid=(.*?)$/m, "_ffbid=#{bid}")
    pkgbuild = pkgbuild.gsub(/^# Next version:.*?$/m, "# Next version: #{version}")
    pkgbuild = pkgbuild.gsub(/^# Current BID:.*?$/m, "# Current BID: #{bid}")
    File.write("PKGBUILD", pkgbuild)
  end

  self.run
end
