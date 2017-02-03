require "./automaintainer/*"
require "http/client"
require "xml"
require "openssl"
require "openssl/lib_crypto"

module Automaintainer
  @@configFilePath = "./data/config.yaml"
  @@originalPKGBUILD = "~/ffdev-aur/PKGBUILD"
  @@startingBID = "20170123004004"
  @@startingVersion = "53.0a2"
  @@nextV = "https://aus5.mozilla.org/update/6/Firefox/%VERSION%/%BUILDID%/Linux_x86_64-gcc3/en-US/aurora/Linux/NA/default/default/update.xml?force=1"
  @@downloadURL = "https://download-installer.cdn.mozilla.net/pub/firefox/nightly/latest-mozilla-aurora/firefox-%VERSION%.en-US.linux-%ARCH%.tar.bz2"
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
          puts "New version! #{updEl["appVersion"]} - #{updEl["buildID"]}"
          self.updatePKGBUILD(updEl["appVersion"], updEl["buildID"])
          if config
            config.version = updEl["appVersion"]
            config.buildId = updEl["buildID"]
            self.writeConfig(config)
          end

          if updEl["appVersion"] =~ /^[A-Za-z\.0-9]+$/ && updEl["buildID"] =~/^[0-9]+$/
            stdout = IO::Memory.new
            stderr = IO::Memory.new
            result = Process.run(
              "cp PKGBUILD ~/ffdev-aur/ && cd ~/ffdev-aur/ && makepkg --printsrcinfo > .SRCINFO && git add PKGBUILD .SRCINFO && git commit -m 'Bump to version #{updEl["appVersion"]}, BID: #{updEl["buildID"]}' && git push origin master",
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

    shaSums = {} of String => String

    @@arch.each do |arch|
      url = @@downloadURL.gsub(/%VERSION%/, version)
      url = url.gsub(/%ARCH%/, arch)
      fPath = "/tmp/ff-#{arch}"

      if @@debug == false
        uri = URI.parse url
        host = ""
        host = uri.host.to_s
        path = uri.path.to_s

        client = HTTP::Client.new(host)
        client.compress = false # WTF Mozilla Servers?
        # See https://twitter.com/DenysVitali/status/826878809240645632
        client.get(path) do |response|
          content_length = response.headers["Content-Length"].to_i

          File.open(fPath, "wb") do |file|
            if response.body_io?
              response.body_io.each_byte do |byte|
                file.write_byte(byte)
              end
            end
          end
        end
      end
      sha512 = OpenSSL::SHA512.hash(File.read(fPath)).to_slice.hexstring
      File.delete(fPath)
      puts "#{arch}: #{sha512}"

      regexp = Regex.new("sha512sums_#{arch}=\\('(.*?)'")
      pkgbuild = pkgbuild.gsub(regexp, "sha512sums_#{arch}=('#{sha512}'")
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

class OpenSSL::SHA512
  # Crystal doesn't have SHA512 (before d45fbff38f7cf08ec98d393f610be28139caa81e)
  def self.hash(data : String) : UInt8[64]
    hash(data.to_unsafe, LibC::SizeT.new(data.bytesize))
  end

  def self.hash(data : UInt8*, bytesize : LibC::SizeT) : UInt8[64]
    buffer = uninitialized UInt8[64]
    LibCrypto.sha512(data, bytesize, buffer)
    buffer
  end
end

lib LibCrypto
  fun sha512 = SHA512(data : Char*, length : SizeT, md : Char*) : Char*
end
