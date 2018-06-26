require 'lib/enrichment_integration/dictionary_inputs'

describe Enrichment::TargetSchema do
  include_examples 'dictionary_inputs'

  let(:target_schema) { Enrichment::TargetSchema.new('dave_epstien@weather.com') }
  let(:generated_file) { 'spec/lib/enrichment_integration/fixtures/generated_schema.json' }
  let(:expected_file) { 'spec/lib/enrichment_integration/fixtures/expected_schema.json' }

  before :each do
    stub_const("Enrichment::TargetSchema::FILE_LOCATION", generated_file)
    allow(target_schema).to receive(:dictionary).and_return(dictionary)
    allow(target_schema).to receive(:import).and_return(nil)
    allow(target_schema).to receive(:notify_user).and_return(nil)
  end

  context self do
    it 'serializes the correct target schema' do
      target_schema.generate_and_import
      expect(JSON.parse(File.read(generated_file))).to eq(JSON.parse(File.read(expected_file)))
    end

  end

end
