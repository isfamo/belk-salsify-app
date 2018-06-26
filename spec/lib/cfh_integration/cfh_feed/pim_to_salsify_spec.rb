describe PIMToSalsify do

  let(:date) { Date.today }
  let(:pim_to_salsify) { PIMToSalsify.new(date) }
  let(:ftp) { double('ftp') }
  let(:salsify_client) { double('salsify_client') }
  let(:input_file) { 'spec/lib/cfh_integration/fixtures/pim_import.tar.gz' }

  before :each do
    stub_const('PIMToSalsify::PRODUCT_CONTENT_FILE_LOCATION', 'spec/lib/cfh_integration/cfh_feed/fixtures/generated_product_import.json')
    stub_const('PIMToSalsify::GROUPING_FILE_LOCATION', 'spec/lib/cfh_integration/cfh_feed/fixtures/generated_grouping_import.json')
    stub_const('PIMToSalsify::PARENT_ID_FILE_LOCATION', 'spec/lib/cfh_integration/cfh_feed/fixtures/generated_parent_id_import.json')
    allow(ftp).to receive(:upload).and_return(nil)
    allow(ftp).to receive(:remove).and_return(nil)
    allow(pim_to_salsify).to receive(:salsify_ftp).and_return(ftp)
    allow(pim_to_salsify).to receive(:belk_ftp).and_return(ftp)
    allow(pim_to_salsify).to receive(:belk_qa_ftp).and_return(ftp)
    allow(pim_to_salsify).to receive(:salsify_client).and_return(salsify_client)
    allow(pim_to_salsify).to receive(:remote_file_paths).and_return(nil)
    allow(pim_to_salsify).to receive(:populate_local_files).and_return(nil)
    allow(pim_to_salsify).to receive(:local_file_paths).and_return([])
    allow(pim_to_salsify).to receive(:remove_files_on_ftp).and_return(nil)
    allow(pim_to_salsify).to receive(:archive_files_on_ftp).and_return(nil)
    allow(pim_to_salsify).to receive(:prepare_files).and_return([ PIMToSalsify.extract_pim_export(input_file) ])
    allow(Salsify::Utils::Import).to receive(:start_import_with_new_file).and_return(nil)
    pim_to_salsify.import_pim_feed
  end

  context '#import_product_content' do
    it 'generates the correctly formatted JSON imports' do
      generated_import = JSON.parse(File.read('spec/lib/cfh_integration/cfh_feed/fixtures/generated_product_import.json'))
      expected_import = JSON.parse(File.read('spec/lib/cfh_integration/cfh_feed/fixtures/expected_product_import.json'))
      expect(generated_import).to be_equivalent_to(expected_import)
    end
  end

  context '#import_groupings' do
    it 'generates the correctly formatted JSON imports' do
      generated_import = JSON.parse(File.read('spec/lib/cfh_integration/cfh_feed/fixtures/generated_grouping_import.json'))
      expected_import = JSON.parse(File.read('spec/lib/cfh_integration/cfh_feed/fixtures/expected_grouping_import.json'))
      expect(generated_import).to be_equivalent_to(expected_import)
    end
  end

  context '#import_parent_ids' do
    it 'generates the correctly formatted JSON imports' do
      generated_import = JSON.parse(File.read('spec/lib/cfh_integration/cfh_feed/fixtures/generated_parent_id_import.json'))
      expected_import = JSON.parse(File.read('spec/lib/cfh_integration/cfh_feed/fixtures/expected_parent_id_import.json'))
      expect(generated_import).to be_equivalent_to(expected_import)
    end
  end

end
