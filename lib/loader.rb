require 'yaml'
require 'shellwords'
require 'json'

# Support class to load dev.yml
class Dev
  class << self
    def env(path)
      new(path).env
    end
  end

  attr_reader :path

  def initialize(path)
    @path = path
  end

  def env
    puts "_dev_name=#{Shellwords.escape(name)}"

    put_array('_dev_up', up, &:first)

    put_association('_dev_dependencies', up) { |k, v| [k, assign(v)] }

    put_association('_dev_commands', commands) do |name, script|
      script = script['run'] if script.is_a?(Hash)
      if script.nil?
        warn("missing command: #{name}")
        next
      end

      [name, expand_script(script)]
    end
  end

  private

  UNSET = 'unset _dev_up_value'

  def assign(value)
    return Shellwords.escape(UNSET) if value.nil?

    assignment = case value
    when Hash
      assign_association(value)
    when Array
      assign_array(value)
    else
      assign_scalar(value)
    end

    Shellwords.escape("#{UNSET}; #{assignment}")
  end

  def assign_array(value)
    array = value.map { |v| Shellwords.escape(v) }.join(' ')
    "local -a _dev_up_value=( #{array} )"
  end

  def assign_association(value)
    association = value.map { |k, v| "[#{k}]=#{Shellwords.escape(v)}" }.join(' ')
    "local -A _dev_up_value=( #{association} )"
  end

  def assign_scalar(value)
    string = Shellwords.escape(value.to_s)
    "local _dev_up_value=#{string}"
  end

  def commands
    @commands ||= yaml.fetch('commands', {})
  end

  def default_name
    @default_name ||= File.basename(dirname)
  end

  def dirname
    @dirname ||= File.dirname(@path)
  end

  def expand_script(script)
    script = %(#{script} "$@") if script.lines.size == 1 && !script.include?('$@') && !script.include?('$*')
    Shellwords.escape(script)
  end

  def name
    @name ||= yaml.fetch('name', default_name)
  end

  def put_array(name, values, &block)
    puts "#{name}=("
    values.each { |v| puts "  #{block.call(v)}" }
    puts ")"
  end

  def put_association(name, association, &block)
    put_array(name, association.map(&block)) { |k, v| "[#{k}]=#{v}" }
  end

  def up
    @up ||= yaml.fetch('up', []).map do |dependency|
      case dependency
      when Hash
        dependency.first
      when Array
        dependency
      else
        [dependency]
      end
    end
  end

  def yaml
    @yaml ||= (YAML.load_file(path) || {})
  end
end

Dev.env(ARGV.first)
