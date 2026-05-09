# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe EmTools::Core::Logger do
  around do |ex|
    saved = ENV.to_hash.slice('EM_TOOLS_LOG_LEVEL', 'EM_TOOLS_LOG_OUTPUT', 'EM_TOOLS_LOG_FORMAT')
    %w[EM_TOOLS_LOG_LEVEL EM_TOOLS_LOG_OUTPUT EM_TOOLS_LOG_FORMAT].each { |k| ENV.delete(k) }
    ex.run
  ensure
    %w[EM_TOOLS_LOG_LEVEL EM_TOOLS_LOG_OUTPUT EM_TOOLS_LOG_FORMAT].each { |k| ENV.delete(k) }
    saved.each { |k, v| ENV[k] = v }
  end

  it 'returns an info-level Logger by default with the given progname' do
    io = StringIO.new
    logger = described_class.for(progname: 'unit-test', output: io)

    expect(logger).to be_a(::Logger)
    expect(logger.level).to eq(::Logger::INFO)
    expect(logger.progname).to eq('unit-test')

    logger.debug('hidden')
    logger.info('visible')

    expect(io.string).not_to include('hidden')
    expect(io.string).to include('INFO')
    expect(io.string).to include('[unit-test]')
    expect(io.string).to include('visible')
  end

  it 'honors EM_TOOLS_LOG_LEVEL when no explicit level is given' do
    ENV['EM_TOOLS_LOG_LEVEL'] = 'debug'
    io = StringIO.new
    logger = described_class.for(progname: 'env', output: io)

    logger.debug('shown-now')
    expect(io.string).to include('DEBUG')
    expect(io.string).to include('shown-now')
  end

  it 'falls back to INFO for unknown EM_TOOLS_LOG_LEVEL values' do
    ENV['EM_TOOLS_LOG_LEVEL'] = 'totally-bogus'
    logger = described_class.for(output: StringIO.new)
    expect(logger.level).to eq(::Logger::INFO)
  end

  it 'emits valid JSON one-per-line when format=json' do
    io = StringIO.new
    logger = described_class.for(progname: 'json-test', output: io, format: 'json')

    logger.info('hello')
    line = io.string.lines.first
    parsed = JSON.parse(line)
    expect(parsed).to include('level' => 'INFO', 'progname' => 'json-test', 'message' => 'hello')
    expect(parsed['time']).to match(/\A\d{4}-\d{2}-\d{2}T/)
  end

  it 'silent! returns a fatal-level NULL logger and sets EM_TOOLS_LOG_LEVEL=fatal' do
    saved_root = described_class.instance_variable_get(:@root)
    described_class.instance_variable_set(:@root, nil)
    logger = described_class.silent!
    expect(logger.level).to eq(::Logger::FATAL)
    expect(ENV['EM_TOOLS_LOG_LEVEL']).to eq('fatal')
  ensure
    described_class.instance_variable_set(:@root, saved_root)
  end

  it 'root is shared across calls until reassigned' do
    described_class.instance_variable_set(:@root, nil)
    a = described_class.root
    b = described_class.root
    expect(a).to equal(b)
    custom = ::Logger.new(IO::NULL)
    described_class.root = custom
    expect(described_class.root).to equal(custom)
  ensure
    described_class.instance_variable_set(:@root, nil)
  end
end
