describe Demandware::XMLGenerator do

  before :all do
    @output_file = '/tmp/output.xml'
    File.delete(@output_file) if File.exists?(@output_file)
  end

  after :all do
    SalsifySqlNode.delete_all
    CfhExecutionError.delete_all
    SalsifyCfhExecution.delete_all
  end

  before :each do
    allow_any_instance_of(Demandware::Groupings).to receive(:skus).and_return([])
  end

  context 'def create_from_category_tree(tree)' do
    before :each do
      today_exec = SalsifyCfhExecution.auto_today.first_or_create
      csv = CustomCSV::Wrapper.new('./spec/lib/cfh_integration/cfh_utils/category_hierarchy.csv')

      csv.foreach do |node|
        hash = node.to_h
        SalsifySqlNode.new(parent_sid: hash[:salsifyparent_id], sid: hash[:salsifyid], salsify_cfh_execution_id: today_exec.id, data: {
          name: hash[:salsifyname],
          list_id: Faker::Number.number(4)
        }).save!
        SalsifySqlNode.new(node_type: "product", parent_sid: hash[:salsifyid], sid: Faker::Lorem.characters(6), salsify_cfh_execution_id: today_exec.id, data: {
          name: Faker::Commerce.product_name,
          list_id: Faker::Number.number(4)
        }).save!
      end

      # add grouping to a category
      product = today_exec.salsify_sql_nodes.products.last
      product.data = { groupings: '123456789', list_id: 1234 }
      product.save!
      [ 'abc', 'def', 'ghi' ].each do |sid|
        dup_product = product.dup
        dup_product.sid = sid
        product.data = { groupings: '123456789', list_id: 1234 }
        dup_product.save!
      end

      # add additional products with matching groupings to a difference category
      product = today_exec.salsify_sql_nodes.products.first
      product.data = { groupings: '123456789', list_id: 1234 }
      product.save!
      [ 'abc', 'def', 'ghi' ].each do |sid|
        dup_product = product.dup
        dup_product.sid = sid
        product.data = { groupings: '123456789', list_id: 1234 }
        dup_product.save!
      end

      # same scenario but with an :only grouping condition grouping to a category
      product = today_exec.salsify_sql_nodes.products[100]
      product.data = { groupings: '123456789', grouping_condition: 'Only', list_id: 1234 }
      product.save!
      [ 'abc', 'def', 'ghi' ].each do |sid|
        dup_product = product.dup
        dup_product.sid = sid
        product.data = { groupings: '123456789', grouping_condition: 'Only', list_id: 1234 }
        dup_product.save!
      end

      # XXX this shouldn't be namespaced
      category_metadata = SalsifyToDemandware::CategoryMetadata.new('salsify_client', today_exec)
      category_metadata_data = CSV.read(open('spec/lib/cfh_integration/cfh_utils/current_category_metadata.csv'), headers: true)
      category_metadata.send(:upsert_rows, category_metadata_data)

      tree = SalsifyTree.new(today_exec.salsify_sql_nodes, :added)
      # We want those nodes added so we can test
      tree.root.each { |node| node.delta_status = :updated }

      obj = Demandware::XMLGenerator.new(@output_file)
      obj.create_from_category_tree(tree)

      content = File.read(@output_file)
      @xml_doc = Nokogiri::XML(content)
      File.open('spec/lib/cfh_integration/cfh_utils/generated_cfh.xml', 'w') { |file| file.write(@xml_doc.to_xml) }
    end

    it 'should have the catalog' do
      expect(@xml_doc.xpath("//xmlns:catalog").count).to eq(1)
    end

    it 'should have 851 categories in the catalog' do
      expect(@xml_doc.xpath("//xmlns:category").count).to eq(851)
    end

    # TODO figure out how to represent page attributes
    xit 'should have the correct attributes for the first category' do
      category = @xml_doc.xpath('//xmlns:category')[0]
      expect(category.at('display-name').content).to eq('Bed & Bath')
      expect(category.at('parent').content).to eq('root')
      expect(category.at('online-flag')).to eq nil
      # expect(category.at('page-attributes//page-title').content).to eq('Beauty')
      # expect(category.at('page-attributes//page-description').content).to eq('Beauty')
    end

    it 'should have the correct attributes for all the products' do
      expect(@xml_doc.xpath('//xmlns:category-assignment').count).to eq(860)
    end

    context 'products' do

      let(:product_node) { @xml_doc.xpath('//xmlns:category-assignment[@category-id="beauty"]').first }

      it 'has the correct primary-flag' do
        expect(product_node.at('primary-flag').content).to eq 'true'
      end

      it 'has the correct online-to flag' do
        expect(product_node.at('online-to').content).to eq '2016-12-15T04:59:00'
      end

      it 'has the correct online-from flag' do
        expect(product_node.at('online-from').content).to eq '2016-12-14T05:00:00'
      end

    end
  end

  context '#create_from_grouped_skus(products)' do
    before(:each) do
      @obj = Demandware::XMLGenerator.new(@output_file)
      3.times { FactoryGirl.create(:cma_event, sku_code: 'SAMESKUCODE') }

      @obj.create_from_grouped_skus(CMAEvent.all.group_by(&:sku_code), [], [], CMAEvent.all.map(&:sku_code))

      content = File.read(@output_file)
      @xml_doc = Nokogiri::XML(content)
    end

    it 'should have the catalog' do
      expect(@xml_doc.xpath("//xmlns:catalog").count).to eq(1)
    end

    it 'should have one product in the catalog' do
      expect(@xml_doc.xpath("//xmlns:product").count).to eq(1)
    end

    it 'should have two custom-attributes for all three events, eventCodeID & currentEventCodeID' do
      expect(@xml_doc \
        .xpath("//xmlns:product")[0] \
        .search("custom-attribute") \
        .count).to be(2)
    end

    it 'should have one eventCodeID custom-attribute with six values' do
      expect(@xml_doc.xpath(
        "//xmlns:custom-attribute[@attribute-id='eventCodeID']/xmlns:value"
      ).count).to eq 6
    end

    it 'should have one currentEventCodeID custom-attribute with six values' do
      expect(@xml_doc.xpath(
        "//xmlns:custom-attribute[@attribute-id='currentEventCodeID']/xmlns:value"
      ).count).to eq 1
    end
  end

  context '#create_from_grouped_skus(products)' do
    before(:each) do
      @obj = Demandware::XMLGenerator.new(@output_file)

      FactoryGirl.create(:cma_event,
        end_date: DateTime.strptime("#{yesterday} 1000 #{offset}", strp_format))
      FactoryGirl.create(:cma_event, start_date: 10.minutes.ago,
        end_date: 1.day.from_now, adevent: 'NONEVENT', sku_code: '1a2b3c4d5e6f')

      @obj.create_from_grouped_skus(CMAEvent.all.group_by(&:sku_code), [], [], CMAEvent.all.map(&:sku_code))

      content = File.read(@output_file)
      @xml_doc = Nokogiri::XML(content)
    end

    it 'should have two products' do
      expect(@xml_doc.xpath('//xmlns:product').count).to eq(2)
    end

    it 'should have the first product with no eventCodeId value' do
      expect(
        @xml_doc.xpath('//xmlns:product').first.
          xpath(".//xmlns:custom-attribute[@attribute-id='eventCodeID']/xmlns:value").count
      ).to eq(0)
    end

    it 'should have the second product with only one present value' do
      expect(
        @xml_doc.xpath('//xmlns:product')[1].
          xpath(".//xmlns:custom-attribute[@attribute-id='eventCodeID']/xmlns:value").count
      ).to eq(1)
    end
  end

  context '#create_from_grouped_skus(products)' do
    before(:each) do
      @obj = Demandware::XMLGenerator.new(@output_file)

      2.times { FactoryGirl.create(:cma_event, adevent: "SAME", sku_code: "SAMESKUCODE") }
      @obj.create_from_grouped_skus(CMAEvent.all.group_by(&:sku_code), [], [], CMAEvent.all.map(&:sku_code))

      content = File.read(@output_file)
      @xml_doc = Nokogiri::XML(content)
    end

    it 'should have only 3 values' do
      expect(
        @xml_doc.xpath('//xmlns:product').first.
          xpath(".//xmlns:custom-attribute[@attribute-id='eventCodeID']/xmlns:value").count
      ).to eq(3)
    end
  end
end

describe Demandware::XMLParser do
  context '#initialize' do
    it 'should raise an error if the file is missing' do
      expect {
        Demandware::XMLParser.new(['random'])
      }.to raise_error(Demandware::MissingXMLFile)
    end
  end

  context '#all_to_json' do
    before(:all) do
      @xml_file = 'spec/lib/cfh_integration/cfh_utils/sample_product.xml'
      @json_file = 'spec/lib/cfh_integration/cfh_utils/sample_product.json'
      @tmp_file = 'spec/lib/cfh_integration/cfh_utils/unit-test-all_to_json.json'
      @dw = Demandware::XMLParser.new([@xml_file])
      json = JSON.parse(File.read(@json_file))

      File.open(@tmp_file, "wb") do |file|
        @dw.all_to_json(file)
      end

      expected_products = json[1]["products"]
      actual_products = JSON.load(File.read(@tmp_file))[4]["products"]

      # First Product
      @x = expected_products[0].symbolize_keys!
      @y = actual_products[0].symbolize_keys!
    end


    it 'should have the same attributes' do
      attributes = JSON.load(File.read(@tmp_file))[1]["attributes"]
      grouped = attributes.group_by{|x| x["salsify:data_type"]}.inject({}){|c,(k,v)| c[k] = v.count; c}

      expect(grouped).to eq({"string"=>69, "digital_asset"=>2, "date"=>1})
    end

    it 'should have the same keys' do
      #### KEYS DIFF ####
      begin
        expect(@x.keys.count).to eq(@y.keys.count)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        if @x.keys.count > @y.keys.count
          puts "Expected has extra keys: #{@x.keys - @y.keys}"
        else
          puts "Actual has extra keys: #{@y.keys - @x.keys}"
        end
        raise e
      end
    end

    it 'should have the same values' do
      #### VALUES DIFF ####
      @x.each do |k,v|
        begin
          expect(v.to_s).to eq(@y[k].to_s)
        rescue RSpec::Expectations::ExpectationNotMetError => e
          puts "Key is: #{k}"
          raise e
        end
      end
    end

    it 'should work for two xml files' do
      @xml_file = './spec/lib/cfh_integration/cfh_utils/sample_product.xml'
      @dw = Demandware::XMLParser.new([@xml_file, @xml_file])

      File.open(@tmp_file, "wb") do |file|
        @dw.all_to_json(file)
      end

      actual_products = JSON.load(File.read(@tmp_file))[4]["products"]
      actual_attributes = JSON.load(File.read(@tmp_file))[1]["attributes"]

      expect(actual_products.count).to eq(4)
      expect(actual_attributes.count).to eq(72)
    end

    after(:all) do
      File.delete(@tmp_file)
    end
  end

  context '#product_sets_to_json' do
    it 'should expand the \'product\' type products to multiple json products' do
      @xml_file = 'spec/lib/cfh_integration/cfh_utils/aggregated_sample.xml'
      @json_file = 'spec/lib/cfh_integration/cfh_utils/grouping_import.json'
      @tmp_file = 'spec/lib/cfh_integration/cfh_utils/unit-test-product_sets_to_json.json'

      @dw = Demandware::XMLParser.new([@xml_file])
      @expected = JSON.parse(File.read(@json_file))[2]["products"]

      File.open(@tmp_file, "wb") do |file|
        @dw.product_sets_to_json(file)
      end
      @actual = JSON.load(File.read(@tmp_file))[3]["products"]
      @actual.each { |x| x.slice!("Groupings", "product_id")}

      @expected.each do |exp|
        search = @actual.find{|x| exp["product_id"] == x["product_id"] && exp["Groupings"] == x["Groupings"]}
        begin
          expect(search).to be_present
        rescue RSpec::Expectations::ExpectationNotMetError => e
          puts "Searched is: #{exp}"
          puts "Actual is: #{@actual}"
          raise e
        end
      end

      File.delete(@tmp_file)
    end
  end

  context '#variants_to_json' do
    # What about the other two <variants product-id> which do not correspond to a product?
    it 'should have `salsify:parent_id` for the variants' do
      @xml_file = 'spec/lib/cfh_integration/cfh_utils/aggregated_sample.xml'
      @json_file = 'spec/lib/cfh_integration/cfh_utils/parent_id_import.json'
      @tmp_file = 'spec/lib/cfh_integration/cfh_utils/unit-test-variants_to_json.json'

      @dw = Demandware::XMLParser.new([@xml_file])

      @expected = JSON.parse(File.read(@json_file))[1]["products"]

      File.open(@tmp_file, "wb") do |file|
        @dw.variants_to_json(file)
      end

      @actual = JSON.load(File.read(@tmp_file))[3]["products"]
      @actual.each { |x| x.slice!("product_id", 'salsify:parent_id')}

      @expected.each do |exp|
        search = @actual.find{|x| exp["product_id"] == x["product_id"] && exp["salsify:parent_id"] == x['salsify:parent_id']}
        begin
          expect(search).to be_present
        rescue RSpec::Expectations::ExpectationNotMetError => e
          puts "Searched is: #{exp}"
          puts "Actual is: #{@actual}"
          raise e
        end
      end
      File.delete(@tmp_file)
    end
  end
end

describe Demandware::XMLParser::XMLProduct do
  before(:all) do
    @xml_file = './spec/lib/cfh_integration/cfh_utils/aggregated_sample.xml'
    @dw = Demandware::XMLParser.new([@xml_file])
    @products = @dw.products
  end

  context '#product?' do
    it 'should have one' do
      result = @products.map { |p| p.product?}
      expect(result).to eq([false, true, false, false])
    end
  end

  context '#variant?' do
    it 'should have one' do
      result = @products.map { |p| p.variant?}
      expect(result).to eq([false, false, true, false])
    end
  end

  context '#parent?' do
    it 'should have three' do
      result = @products.map { |p| p.parent?}
      expect(result).to eq([true, true, false, true])
    end
  end
end

describe Demandware::PIMAttributesMap do
  before(:all) do
    @map = Demandware::PIMAttributesMap.new
  end

  context '#data_type' do
    it 'should return string if key is missing' do
      expect(@map.data_type(:missing)).to eq("string")
      expect(@map.data_type("missing")).to eq("string")
    end

    it 'should return string for set-of-strings records' do
      expect(@map.data_type("refinementSize")).to eq("string")
      expect(@map.data_type(:refinementSize)).to eq("string")
    end

    it 'should return string for string' do
      expect(@map.data_type("nrfColorCode")).to eq("string")
      expect(@map.data_type(:nrfColorCode)).to eq("string")
    end

    it 'should return string for string' do
      expect(@map.data_type("nrfColorCode")).to eq("string")
      expect(@map.data_type(:nrfColorCode)).to eq("string")
    end

    it 'should return boolean for boolean' do
      expect(@map.data_type("il_eligible")).to eq("boolean")
      expect(@map.data_type(:il_eligible)).to eq("boolean")
    end

    it 'should return date for date' do
      expect(@map.data_type("discontinuedDate")).to eq("date")
      expect(@map.data_type(:discontinuedDate)).to eq("date")
    end

    it 'should return number for int' do
      expect(@map.data_type("productDimensionsLength")).to eq("number")
      expect(@map.data_type(:productDimensionsLength)).to eq("number")
    end

    it 'should return digital_asset for images and swatch_images' do
      expect(@map.data_type("swatch_images")).to eq("digital_asset")
      expect(@map.data_type(:swatch_images)).to eq("digital_asset")

      expect(@map.data_type("images")).to eq("digital_asset")
      expect(@map.data_type(:images)).to eq("digital_asset")
    end
  end

  context '#format_values' do
    it 'should modify to string string values' do
      object = {
        shippingDimensionsUOM: true
      }
      @map.format_values(object)
      expect(object[:shippingDimensionsUOM]).to eq("true")
    end

    it 'should modify to int number values' do
      object = {
        productWeight: "100",
        will_not_fail: "will_not_fail"
      }
      @map.format_values(object)

      expect(object[:productWeight]).to eq(100)
      expect(object[:will_not_fail]).to eq("will_not_fail")
    end

    it 'should modify to float number values - string passed' do
      object = {
        productWeight: "100.5",
        will_not_fail: "will_not_fail"
      }
      @map.format_values(object)

      expect(object[:productWeight]).to eq(100.5)
      expect(object[:will_not_fail]).to eq("will_not_fail")
    end

    it 'should modify to float number values - float passed' do
      object = {
        productWeight: 100.5,
        will_not_fail: "will_not_fail"
      }
      @map.format_values(object)

      expect(object[:productWeight]).to eq(100.5)
      expect(object[:will_not_fail]).to eq("will_not_fail")
    end

    it 'shoud format dates to %Y-%m-%d' do
      object = {
        skuActiveStartDate: "2016-04-14T00:00:00-0400",
        GXS_PDU_Available_Date: "2016-12-30T00:00:00-0500",
        will_not_fail: "will_not_fail"
      }
      @map.format_values(object)

      expect(object[:skuActiveStartDate]).to eq("2016-04-14")
      expect(object[:GXS_PDU_Available_Date]).to eq("2016-12-30")
      expect(object[:will_not_fail]).to eq("will_not_fail")
    end
  end
end
