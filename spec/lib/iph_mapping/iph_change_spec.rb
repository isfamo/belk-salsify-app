require './lib/iph_mapping/iph_constants.rb'
require './lib/iph_mapping/iph_change.rb'
require './lib/iph_mapping/iph_mapper.rb'
require './lib/iph_mapping/iph_config.rb'
require './lib/helpers/salsify_import.rb'
require './lib/helpers/salsify_filter.rb'
require './lib/helpers/dirs.rb'
require './spec/lib/iph_mapping/fixtures/dictionary/dictionary_inputs'
ENV['CARS_ENVIRONMENT'] = 'test'
ENV['SALSIFY_SUPERUSER_TOKEN'] = 'mytoken'

describe IphMapping::IphChange do
  include_examples 'dictionary_inputs_iph_mapping'

  describe 'Generate correct iph update json' do

    let(:fixtures_dir) { './spec/lib/iph_mapping/fixtures' }
    let(:generated_dir) { File.join(fixtures_dir, 'generated') }

    let(:org_id) { ENV['CARS_ORG_ID'].to_i }
    let(:webhook_name) { 'iph_change_test' }
    let(:styles_json) { File.read(File.join(fixtures_dir, 'input_products.json')) }
    let(:skus_by_style_id) { Oj.load(File.read(File.join(fixtures_dir, 'input_skus_by_style_id.json'))) }
    let(:iph_change) { IphMapping::IphChange.new(org_id: org_id, webhook_name: webhook_name, styles: Oj.load(styles_json)) }

    let(:generated_output_filename) { 'generated_import.json' }
    let(:generated_output_filepath) { File.join(generated_dir, generated_output_filename) }
    let(:expected_output_filepath) { File.join(fixtures_dir, 'expected_import.json') }
    let(:expected_output) { Oj.load(File.read(expected_output_filepath)) }

    let(:config_json_path) { File.join(fixtures_dir, 'gxs_iph_config.json') }

    before :each do
      stub_const("IphMapping::FILE_LOCATION_IPH_MAPPING", config_json_path)
      allow(iph_change).to receive(:import_filepath).and_return(generated_output_filepath)
      allow(iph_change).to receive(:skus_by_style_id).and_return(skus_by_style_id)
      allow_any_instance_of(IphMapping::IphConfig).to receive(:iph_config_file_path).and_return(config_json_path)
      allow_any_instance_of(IphMapping::IphMapper).to receive(:data_dictionary).and_return(dictionary)
      allow_any_instance_of(IphMapping::IphMapper).to receive(:timestamp_date).and_return('2017-12-18')
      allow_any_instance_of(IphMapping::IphMapper).to receive(:timestamp_time).and_return('133000')
      allow_any_instance_of(SalsifyImport).to receive(:run_import).and_return(nil)
      allow_any_instance_of(SalsifyImport).to receive(:generate_import_id).and_return(nil)
    end

    context self do
      it 'should generate correct import json' do
        iph_change.process
        generated = load_generated_import
        expect(generated == expected_output).to equal(true)
      end
    end

    def load_generated_import
      Oj.load(File.read(generated_output_filepath))
    end

  end

end
