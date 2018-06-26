describe ProcessCMAFeed do

  let(:date) { Date.strptime('2016-12-12') }
  let(:process_cma_feed) { ProcessCMAFeed.new(date) }
  let(:ftp) { double('ftp') }
  let(:input_filepath) { 'spec/lib/cfh_integration/fixtures/PRICEBOOK_SALSIFY_20161110_1724.tar.gz' }
  let(:csv_input_filepath) { 'spec/lib/cfh_integration/fixtures/PRICEBOOK_SALSIFY_20161110.csv' }
  let(:generated_file) { 'spec/lib/cfh_integration/cma_feed/fixtures/cma-feed-20161212.xml' }
  let(:expected_file) { 'spec/lib/cfh_integration/cma_feed/fixtures/expected_cma_feed.xml' }
  let(:expected_import_file) { 'spec/lib/cfh_integration/cma_feed/fixtures/expected_import.json' }
  let(:generated_import_file) { 'spec/lib/cfh_integration/cma_feed/fixtures/generated_import.json' }
  let(:postmark_client) { double('postmark_client') }

  before :each do
    Timecop.freeze(Time.local(2017, 01, 15))
    seed_database
    stub_const("ProcessCMAFeed::EXTRACT_DIR", 'spec/lib/cfh_integration/cma_feed/fixtures')
    stub_const("ProcessCMAFeed::SALSIFY_IMPORT_FILE_LOCATION", generated_import_file)
    allow(process_cma_feed).to receive(:salsify_ftp).and_return(ftp)
    allow(process_cma_feed).to receive(:belk_ftp).and_return(ftp)
    allow(process_cma_feed).to receive(:belk_qa_ftp).and_return(ftp)
    allow(ftp).to receive(:find_file).and_return('placeholder')
    allow(ftp).to receive(:find_file_with_retry).and_return('placeholder')
    allow(ftp).to receive(:download).and_return(nil)
    allow(ftp).to receive(:upload).and_return(nil)
    allow(ftp).to receive(:remove).and_return(nil)
    allow(process_cma_feed).to receive(:csv_local_filepath).and_return(csv_input_filepath)
    allow(process_cma_feed).to receive(:input_filepath).and_return(input_filepath)
    allow(process_cma_feed).to receive(:unzip_file).and_return(nil)
    allow(process_cma_feed).to receive(:add_headers_to_csv).and_return(nil)
    allow(process_cma_feed).to receive(:run_salsify_import).and_return(nil)
    allow(postmark_client).to receive(:deliver).and_return(true)
    allow_any_instance_of(EmailNotifier).to receive(:postmark_client).and_return(postmark_client)
  end

  context self do
    it 'generates the correctly formatted XML' do
      process_cma_feed.run
      generated_xml = Nokogiri::XML(File.read(generated_file))
      expected_xml = Nokogiri::XML(File.read(expected_file))
      generated_import = JSON.parse(File.read(generated_import_file))
      expected_import = JSON.parse(File.read(expected_import_file))
      expect(generated_xml).to be_equivalent_to(expected_xml)
      expect(generated_import).to be_equivalent_to(expected_import)
      expect(JobStatus.find_by(title: 'cma').status).to eq 'Finished Processing'
    end
  end

  context 'email notifier' do
    it 'responds without errors' do
      expect(process_cma_feed.send_notification_email).to eq true
    end

    it 'responds with errors' do
      expect(process_cma_feed.send_notification_email(error: 'ERROR!')).to eq true
    end
  end

  def seed_database
    current_skus = [
      '0000400063830215',
      '0000400064110033',
      '0000400418133299',
      '0000934724738746',
      '0000400063830999',
      '0000400063830876',
      '0000400063830877',
      '0000400063830978'
    ]
    outdated_skus = [ '0000400282601481' ]
    seed_skus(current_skus, date - 5.day)
    seed_skus(outdated_skus, date - 35.day)
    seed_parent
  end

  def seed_skus(skus, date)
    skus.each { |sku| Sku.create!(product_id: sku, inventory_reset_date: date) }
  end

  def seed_parent
    parent = ParentProduct.create!(product_id: '1654443JF67238JH00')
    sku = Sku.find_or_create_by(product_id: '0000400418133299')
    sku.update_attributes(parent_id: parent.product_id, inventory_reset_date: date)
  end

end
