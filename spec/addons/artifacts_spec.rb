require 'ostruct'
require 'spec_helper'

describe Travis::Build::Script::Addons::Artifacts, :sexp do
  let(:config) { { key: 'key', secret: 'secret', bucket: 'bucket', private: true } }
  let(:data)   { PAYLOADS[:push].deep_clone }
  let(:sh)     { Travis::Shell::Builder.new }
  let(:addon)  { described_class.new(sh, Travis::Build::Data.new(data), config) }
  subject      { sh.to_sexp }

  before :each do
    addon.validator.stubs(valid?: true)
    addon.after_script
  end

  describe 'with a valid config' do
    describe 'exports' do
      let(:exports) { sexp_filter(subject, [:export]) }

      it 'exports env vars' do
        expect(exports).not_to be_empty
      end

      it 'quotes env var values' do
        expect(exports.last.last.last).to match(/^".*"$/)
      end
    end

    it 'installs artifacts' do
      should include_sexp [:raw, addon.template('install.sh')]
    end

    it 'runs the command' do
      should include_sexp [:cmd, 'artifacts upload']
    end
  end

  describe 'with an invalid config' do
    before :each do
      addon.validator.stubs(valid?: false)
      addon.validator.stubs(errors: ['kaputt 1', 'kaputt 2'])
    end

    it 'echoes the messages' do
      addon.after_script
      should include_sexp [:echo, 'kaputt 1', ansi: :red], [:echo, 'kaputt 2', ansi: :red]
    end

    it 'does not run the addon' do
      subject.expects(:run).never
      addon.after_script
    end
  end
end

