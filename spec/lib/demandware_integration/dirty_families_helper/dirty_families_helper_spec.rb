require './lib/demandware_integration/dirty_families_helper.rb'
require './lib/demandware_integration/salsify_helper.rb'
require './lib/demandware_integration/s3_helper.rb'
require './lib/demandware_integration/dw_constants.rb'
ENV['CARS_ENVIRONMENT'] = 'test'
ENV['SALSIFY_SUPERUSER_TOKEN'] = 'abc'
ENV['testing'] = 'true'

describe Demandware::DirtyFamiliesHelper do

  describe 'Identify Updated Product Families' do

    let(:datetime_now) { DateTime.new(2018, 3, 20, 13, 45, 0) }
    let(:dirty_families_helper) { Demandware::DirtyFamiliesHelper.new(datetime_now, (datetime_now - (1.0 / 24.0)), false) }
    let(:salsify_helper) { Demandware::SalsifyHelper.new }

    let(:fixtures_dir) { 'spec/lib/demandware_integration/dirty_families_helper/fixtures' }
    let(:updated_products_hash) { load_json_fixture('updated_products_20180320.json') }
    let(:grouping_products_hash) { load_json_fixture('grouping_products_20180320.json') }
    let(:expected_affected_groupings_hash) { load_json_fixture('expected_affected_groupings_20180320.json') }
    let(:expected_queried_style_ids_from_groupings) { load_json_fixture('expected_queried_style_ids_20180320.json') }

    let(:generated_output_location) { 'spec/lib/demandware_integration/dirty_families_helper/fixtures' }
    let(:generated_output_filename) { 'generated_dirty_families_hash.json' }

    before :each do
      stub_const("Demandware::LOCAL_PATH_UPDATED_PRODUCTS_JSON", generated_output_location)
      stub_const("Demandware::FILENAME_UPDATED_PRODUCTS_JSON", generated_output_filename)
      allow(DateTime).to receive(:now).and_return(datetime_now)
      allow(dirty_families_helper).to receive(:initial_check_updated_products_count).and_return(1)
      allow(dirty_families_helper).to receive(:updated_product_by_id).and_return(updated_products_hash)
      allow(dirty_families_helper).to receive(:exported_grouping_products).and_return(grouping_products_hash)
    end

    context self do
      it 'queries the correct set of product ids' do
        expect(dirty_families_helper.affected_grouping_by_id).to eq(expected_affected_groupings_hash)
        expect(dirty_families_helper.grouping_child_style_ids).to eq(expected_queried_style_ids_from_groupings)
      end
    end

    def load_json_fixture(name)
      Oj.load(File.read(File.join(fixtures_dir, name)))
    end

  end

end
