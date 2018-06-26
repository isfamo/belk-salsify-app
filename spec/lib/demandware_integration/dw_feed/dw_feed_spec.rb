require './lib/demandware_integration/dw_feed.rb'
require './lib/demandware_integration/dw_xml_generator.rb'
require './lib/demandware_integration/dirty_families_helper.rb'
require './lib/demandware_integration/salsify_helper.rb'
require './lib/demandware_integration/s3_helper.rb'
require './lib/demandware_integration/dw_constants.rb'
require 'lib/enrichment_integration/dictionary_inputs'
ENV['CARS_ENVIRONMENT'] = 'test'
ENV['SALSIFY_SUPERUSER_TOKEN'] = 'mytoken'

describe Demandware::DwFeed do
  include_examples 'dictionary_inputs'

  describe 'Generate correct demandware xml' do

    # The relationship between the start_datetime of dw_feed and
    # the updated dates of products in the fixture is important

    let(:dw_feed) { Demandware::DwFeed.new(since_datetime: (DateTime.new(2017, 9, 19) - (0.5 / 24).to_f), deliver_feed: false, run_pending_skus_update: false) }

    let(:generated_output_location) { 'spec/lib/demandware_integration/dw_feed/fixtures' }
    let(:generated_output_filepath) { 'spec/lib/demandware_integration/dw_feed/fixtures/Catalog_Delta_Salsify_1.xml' }
    let(:exported_attributes) { parse_attributes(CSV.parse(File.read('spec/lib/demandware_integration/dw_feed/fixtures/exported_attributes.csv'), headers: true)) }

    let(:exported_products_filepath) { 'spec/lib/demandware_integration/dw_feed/fixtures/exported_products_1.json' }
    #let(:exported_products) { Oj.load(File.read('spec/lib/demandware_integration/dw_feed/fixtures/exported_products_1.json')) }
    let(:expected_output_filepath) { 'spec/lib/demandware_integration/dw_feed/fixtures/expected_output_1.xml' }

    before :each do
      stub_const("Demandware::LOCAL_PATH_DW_FEED_XMLS", generated_output_location)
      stub_const("Demandware::LOCAL_PATH_DW_FEED_ZIPS", generated_output_location)
      stub_const("Demandware::DwXmlGenerator::MAX_ITEMS_PER_DW_FILE", 1000000000)
      allow(dw_feed).to receive(:attributes).and_return(exported_attributes)
      allow(dw_feed).to receive(:data_dictionary).and_return(dictionary)
    end

    # TODO: Update tests when Belk confirms expected behavior
    # context self do
    #   it 'case 1 - style updated, style not ready' do
    #     # Should send base alone as offline
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 18, 14)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(1))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results(1)
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case 2 - style updated, style ready, color ready, no colors pending' do
    #     # Should send base alone as online
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(2))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results(2)
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case 3 - style updated, style ready, color ready, colors pending' do
    #     # Should send base and complete skus, should unflag pending skus
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(3))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results(3)
    #     expect(xmls_match?(generated_xml, expected_xml))
    #     expect(dw_feed.sku_ids_to_mark_publish_pending_false.length == 1)
    #     expect(dw_feed.sku_ids_to_mark_publish_pending_true.length == 0)
    #   end
    # end
    #
    # context self do
    #   it 'case 4 - style updated, style ready, no colors ready' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(4))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case 5/6 - color master created/updated, not complete' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('5_6'))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case 7 - color master updated, is complete, style ready' do
    #     # Should send base and complete skus (even for other colors)
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(7))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results(7)
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case 8 - color master updated, is complete, style not ready' do
    #     # Should not trigger a feed, but should flag updated sku as pending
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(8))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #     expect(dw_feed.sku_ids_to_mark_publish_pending_false.length == 0)
    #     expect(dw_feed.sku_ids_to_mark_publish_pending_true.length == 1)
    #   end
    # end
    #
    # # context self do
    # #   it 'case 9 - sku goes from non-master to color master' do
    # #     # Case covered by test cases 5-8 (color master update)
    # #   end
    # # end
    #
    # context self do
    #   it 'case 10 - non-master sku updated, color master not complete' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(10))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case 11/14 - non-master sku updated, color master complete, style ready' do
    #     # Should send style and all complete skus
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('11_14'))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results('11_14')
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case 12/13 - non-master sku updated, color master complete, style not ready' do
    #     # Should not trigger a feed, should flag color master sibling sku as pending
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('12_13'))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #     expect(dw_feed.sku_ids_to_mark_publish_pending_false.length == 0)
    #     expect(dw_feed.sku_ids_to_mark_publish_pending_true.length == 1)
    #     expect(dw_feed.sku_ids_to_mark_publish_pending_true.first == '0438574759893')
    #   end
    # end
    #
    # context self do
    #   it 'case 15 - sku (master or non-master) updated, is il_eligible' do
    #     # Should send IL sku alone
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(15))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results(15)
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case 16 - style updated, style not ready, style deactivated' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(16))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case 17 - style updated, style ready, style deactivated' do
    #     # Should send base as offline
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(17))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results(17)
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case 18 - color master updated, not complete, is deactivated' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(18))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case 19 - color master updated, is complete, is deactivated, style ready' do
    #     # Should send sku alone as offline
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(19))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results(19)
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case 20 - color master updated, is complete, is deactivated, style not ready' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(20))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case 21 - non-master sku updated, is deactivated, style not ready' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(21))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case 22 - non-master sku updated, is deactivated, style ready' do
    #     # Should send deactivated sku alone
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products(22))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results(22)
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # # context self do
    # #   it 'case 23 - style updated, is part of CPG group' do
    # #     # Case covered by test case g1a
    # #   end
    # # end
    # #
    # # context self do
    # #   it 'case 24 - sku updated, is part of SCG/SSG group' do
    # #     # Case covered by test case g1b
    # #   end
    # # end
    # #
    # # context self do
    # #   it 'case 25 - style/sku updated, is part of RCG/BCG/SSG collection' do
    # #     # Case covered by test case g1c
    # #   end
    # # end
    #
    # context self do
    #   it 'case g1a - group triggered by update on style/sku, group ready, is type CPG' do
    #     # Should send group as regular item, should not send style itself
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g1a'))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results('g1a')
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case g1b - group triggered by update on style/sku, group ready, is type SCG/SSG' do
    #     # Should send group as regular item, should not send style itself
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g1b'))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results('g1b')
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case g1c - group triggered by update on style/sku, group ready, is type RCG/BCG/SSG' do
    #     # Should send group as collection, should send updated style as well according to other rules
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g1c'))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results('g1c')
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case g2a - group triggered by update on style/sku, group not ready, is type CPG' do
    #     # Should not trigger feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g2a'))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case g2b - group triggered by update on style/sku, group not ready, is type SCG/SSG' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g2b'))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case g2c - group triggered by update on style/sku, group not ready, is type RCG/BCG/SSG collection' do
    #     # Should not send the collection, should send the updated style if necessary
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g2c'))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results('g2c')
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case g3a/g5a - group created/updated, not ready, is type CPG' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g3a_g5a'))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case g3b/g5b - group created/updated, not ready, is type SCG/SSG' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g3b_g5b'))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case g4a - group updated, is ready, is type CPG' do
    #     # Should send complete sku colors of child styles, should not send child styles as their own items
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g4a'))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results('g4a')
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case g4b - group updated, is ready, is type SCG/SSG' do
    #     # Should send complete sku colors of child skus, should not send the parent styles of those skus
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g4b'))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results('g4b')
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case g6 - group updated, not ready, is type RCG/BCG/GSG collection' do
    #     # Should not trigger a feed
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g6'))
    #
    #     dw_feed.send_feed
    #     expect(!File.exists?(generated_output_filepath))
    #   end
    # end
    #
    # context self do
    #   it 'case g7 - group updated, is ready, is type RCG/BCG/GSG collection' do
    #     # Should send collection with child skus
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g7'))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results('g7')
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case g8a - group deactivated, is ready, is type CPG' do
    #     # Should send grouping as offline, also send child styles and their skus as regular items
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g8a'))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results('g8a')
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end
    #
    # context self do
    #   it 'case g8b - group deactivated, is ready, is type SCG/SSG' do
    #     # Should send grouping as offline, also send child styles and their skus as regular items
    #     dw_feed.start_datetime = DateTime.new(2017, 9, 19)
    #     allow(dw_feed).to receive(:product_families).and_return(load_exported_products('g8b'))
    #
    #     dw_feed.send_feed
    #     generated_xml = Nokogiri::XML(File.read(generated_output_filepath))
    #     expected_xml = load_expected_results('g8b')
    #     expect(xmls_match?(generated_xml, expected_xml))
    #   end
    # end

    def parse_attributes(csv)
      csv.map do |row|
        row_hash = {}
        row.each do |cell_array|
          property = cell_array.first
          value = cell_array.last
          next unless value
          current_val = row_hash[property]
          if current_val
            row_hash[property] = [current_val, value].flatten
          else
            row_hash[property] = value
          end
        end
        row_hash
      end
    end

    def load_exported_products(case_num)
      Oj.load(File.read(exported_products_filepath.gsub('1.json', "#{case_num}.json")))
    end

    def load_expected_results(case_num)
      Nokogiri::XML(File.read(expected_output_filepath.gsub('1.xml', "#{case_num}.xml")))
    end

    def xmls_match?(xml1, xml2)
      xml1.diff(xml2).all? { |change, node| change == ' ' }
    end

  end

end
