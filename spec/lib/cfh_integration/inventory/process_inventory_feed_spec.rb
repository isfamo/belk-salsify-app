describe ProcessInventoryFeed do

  let(:process_inventory_feed) { ProcessInventoryFeed.new }
  let(:ftp) { double('ftp') }
  let(:extracted_file) { 'spec/lib/cfh_integration/inventory/fixtures/inventory.xml' }
  let(:generated_file) { 'spec/lib/cfh_integration/inventory/fixtures/inventory-feed-20161212.xml' }
  let(:expected_import_file) { 'spec/lib/cfh_integration/inventory/fixtures/expected_import.json' }
  let(:generated_import_file) { 'spec/lib/cfh_integration/inventory/fixtures/generated_import.json' }
  let(:expected_file) { 'spec/lib/cfh_integration/inventory/fixtures/expected_output.xml' }
  let(:parent_id_export) { 'spec/lib/cfh_integration/inventory/fixtures/parent_export.json' }
  let(:date) { Date.strptime('2016-12-12') }
  let(:postmark_client) { double('postmark_client') }

  before :each do
    Timecop.freeze(Time.local(2017, 01, 15))
    stub_const("ProcessInventoryFeed::EXTRACT_DIR", 'spec/lib/cfh_integration/inventory/fixtures')
    stub_const("ProcessInventoryFeed::SALSIFY_IMPORT_FILE_LOCATION", generated_import_file)
    allow_any_instance_of(FetchParentsFromSalsify).to receive(:json_export).and_return(JSON.parse(File.read(parent_id_export)))
    allow(process_inventory_feed).to receive(:salsify_ftp).and_return(ftp)
    allow(process_inventory_feed).to receive(:belk_ftp).and_return(ftp)
    allow(process_inventory_feed).to receive(:belk_qa_ftp).and_return(ftp)
    allow(process_inventory_feed).to receive(:date).and_return(date)
    allow(process_inventory_feed).to receive(:unzip_file).and_return(nil)
    allow(process_inventory_feed).to receive(:extracted_file).and_return(extracted_file)
    allow(process_inventory_feed).to receive(:gzip_xml).and_return(nil)
    allow(process_inventory_feed).to receive(:run_salsify_import).and_return(nil)
    allow(ftp).to receive(:find_file).and_return('placeholder')
    allow(ftp).to receive(:download).and_return(nil)
    allow(ftp).to receive(:upload).and_return(nil)
    allow(ftp).to receive(:remove).and_return(nil)
    allow(postmark_client).to receive(:deliver).and_return(true)
    allow_any_instance_of(EmailNotifier).to receive(:postmark_client).and_return(postmark_client)
  end

  context self do
    it 'generates the correct inventory file' do
      seed_database
      process_inventory_feed.run
      generated_xml = Nokogiri::XML(File.read(generated_file))
      expected_xml = Nokogiri::XML(File.read(expected_file))
      generated_import = JSON.parse(File.read(generated_import_file))
      expected_import = JSON.parse(File.read(expected_import_file))
      expect(generated_xml).to be_equivalent_to(expected_xml)
      expect(generated_import).to be_equivalent_to(expected_import)
      expect(JobStatus.find_by(title: 'inventory').status).to eq 'Finished Processing'
    end
  end

  def seed_database
    parent = ParentProduct.find_or_create_by(product_id: 'parent_one', first_inventory_date: '2016-12-12')
    skus = [ '0438539248455', '0438539517209', '0438540818432' ]
    skus.each { |sku| parent.skus.find_or_create_by(product_id: sku, parent_id: parent.product_id) }

    parent = ParentProduct.find_or_create_by(product_id: 'parent_two')
    skus = [ '0438541196256', '0438539544854' ]
    skus.each { |sku| parent.skus.find_or_create_by(product_id: sku, parent_id: parent.product_id) }

    parent = ParentProduct.find_or_create_by(product_id: 'parent_three')
    skus = [ '0438541196249' ]
    skus.each { |sku| parent.skus.find_or_create_by(product_id: sku, parent_id: parent.product_id) }
  end

end
