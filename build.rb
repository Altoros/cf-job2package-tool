require 'yaml'
require 'fileutils'
require 'erb'
require 'ostruct'
require 'json'

class Hash
  def deep_merge(other_hash, &block)
    dup.deep_merge!(other_hash, &block)
  end

  # Same as +deep_merge+, but modifies +self+.
  def deep_merge!(other_hash, &block)
    other_hash.each_pair do |k, v|
      tv = self[k]
      if tv.is_a?(Hash) && v.is_a?(Hash)
        self[k] = tv.deep_merge(v, &block)
      else
        self[k] = block && tv ? block.call(k, tv, v) : v
      end
    end
    self
  end
end

#Converts a.b.c => d to a => {b => { c => d}}
def unflatten(hash)
  res = {}
  hash.each do |key, value|
    keys = key.split('.')
    r = res
    keys.each_with_index do |k, i|
      if (i + 1 == keys.length)
        r[k] = value
      else
        r[k] ||= {}
        r = r[k]
      end
    end
  end
  res
end

class Vars
  attr_reader :properties, :raw_properties, :spec, :name

  def initialize(raw_properties, spec, name)
    @raw_properties = raw_properties
    @properties = open_structize(@raw_properties)
    @spec = spec
    @name = name
  end

  def p(*args)
    names = Array(args[0])
    names.each do |n|
      result = lookup_property(n)
      return result unless result.nil?
    end
    return args[1] if args.length == 2
    puts raw_properties.to_yaml
    raise RuntimeError.new(names)
  end

  def if_p(*names)
    values = names.map do |name|
      value = lookup_property(name)
      return if value.nil?
      value
    end
    yield(*values)
  end

  def lookup_property(key)
    p = @raw_properties
    key.split('.').each do |k|
      p = p[k]
      return nil if p.nil?
    end
    p
  end

  def build(template, filename)
    b = binding
    e = ERB.new(template)
    e.filename = filename
    e.result(b)
  end
end

def open_structize(object)
  case object
  when Hash
    mapped = object.inject({}) { |h, (k, v)| h[k] = open_structize(v); h }
    OpenStruct.new(mapped)
  when Array
    object.map { |v| open_structize(v) }
  else
    object
  end
end

def private_ip
  '192.168.1.72' #`unit-get private-up`
end

def build_template_spec
  unit_name = ENV['JUJU_UNIT_NAME'] || "unit/1"
  unit_index = /.*\/(\d+)$/.match(unit_name)[1].to_i #Extract unit number

  open_structize(index: unit_index, networks: {apps: {ip: private_ip}})
end

if ARGV.length < 2
  puts <<USAGE
  build.rb <job dir> <output dir>
USAGE
  exit 1
end

config = {
  'nats.machines' => ['127.0.0.1'],
  'nats.user' => 'nats',
  'nats.password' => 'nats',
  'nats.port' => 4222,
  'domain' => 'example.net',
  'system_domain' => 'example.net',
  'app_domains' => ['example.net'],
  'ccng.bulk_api_password' => "Password",
  'ccng.db_encryption_key' => "Password",
  'ccdb_ng.db_schema' => 'postgres',
  'ccdb_ng.address' => '127.0.0.1',
  'ccdb_ng.port' => '5432',
  'cc.srv_api_uri' => 'api.127.0.0.1.xip.io',
  'etcd_ips' => ['127.0.0.1'],
  'uaadb.databases' => [{'tag' => 'uaa', 'name' => 'uaadb', 'citext' => true}],
  'uaadb.roles' => [{'tag' => 'admin', 'name' => 'uaadmin', 'password' => 'password'}],
  'ccdb.databases' => [{'tag' => 'cc', 'name' => 'ccdb', 'citext' => true}],
  'ccdb.roles' => [{'tag' => 'admin', 'name' => 'ccadmin', 'password' => 'password'}],
  'ccdb_ng.databases' => [{'tag' => 'cc', 'name' => 'ccdb', 'citext' => true}],
  'ccdb_ng.roles' => [{'tag' => 'admin', 'name' => 'ccadmin', 'password' => 'password'}],
  'ccng.staging_upload_password' => 'Password',
  'ccng.quota_definitions' => {"full" =>
    {"non_basic_services_allowed" => true,
      "total_services" => 20,
      "memory_limit" => 100,
      "total_routes" => 10,
      "trial_db_allowed" => false
    }},
} #YAML.load(`config-get --format=yaml --all`)

spec = YAML.load(File.read(File.join(ARGV[0], 'spec')))

default_properties = spec['properties']

templates = spec['templates']

template_spec = build_template_spec

d = Hash[default_properties.map { |k, v| [k, v['default']] }]
d['networks.apps'] = 'apps'
defaults = unflatten(d)

props = defaults.deep_merge(unflatten(config)) { |k, s, ds| ds || s }
vars = Vars.new(props, template_spec, spec['name'])


templates.each do |template, dest_name|
  dest = File.join(ARGV[1], dest_name)
  FileUtils.mkdir_p(File.dirname(dest))
  File.open(dest, "w") do |f|
    file_name = File.join(ARGV[0], 'templates', template)
    f << vars.build(File.read(file_name), file_name)
  end
end
