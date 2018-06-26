shared_examples 'dictionary_inputs_iph_mapping' do

  let(:dictionary) { Enrichment::Dictionary.new }
  let(:google_sheet) { Enrichment::Dictionary::GoogleSheet.new }
  let(:attributes) { CSV.read('spec/lib/iph_mapping/fixtures/dictionary/attributes.csv', headers: true) }
  let(:attribute_values) { CSV.read('spec/lib/iph_mapping/fixtures/dictionary/attribute_values.csv', headers: true) }
  let(:category_lookup_data) {
    [
      { category_mapping: '', category: 'Women > Pants_and_Leggings', attribute: 'Care', attribute_values: '', category_specific: 'true' },
      { category_mapping: '', category: 'Women > Pants_and_Leggings', attribute: 'Advertised_Origin', attribute_values: '', category_specific: 'true' },
      { category_mapping: '', category: 'Women > Pants_and_Leggings', attribute: 'Hosiery Features', attribute_values: '', category_specific: 'true' },
      { category_mapping: '', category: 'Women > Pants_and_Leggings > Leggings', attribute: 'Advertised_Origin', attribute_values: '', category_specific: 'true' },
      { category_mapping: '', category: 'Women > Pants_and_Leggings > Leggings', attribute: 'Closure Style', attribute_values: '', category_specific: 'true' },
      { category_mapping: '', category: 'Women > Pants_and_Leggings > Jeans', attribute: 'Exterior Features', attribute_values: '', category_specific: 'true' },
      { category_mapping: '', category: 'Women > Pants_and_Leggings > Jeans', attribute: 'Closure Type', attribute_values: '', category_specific: 'true' }
    ]
  }
  let(:iph_lookup_data) {
    [
      { dept: '111', class: '1110', eis_hier_iph_name: 'Women > Coats > Puffer', 'iphCategory' => 'Women > Coats > Puffer' },
      { dept: '111', class: '1110', eis_hier_iph_name: 'Women > Coats > Vest', 'iphCategory' => 'Women > Coats > Vest' },
      { dept: '113', class: '1112', eis_hier_iph_name: 'Women > Coats > Parka', 'iphCategory' => 'Women > Coats > Parka' },
      { dept: '114', class: '1113', eis_hier_iph_name: 'For the Home > Bath', 'iphCategory' => 'For the Home > Bath' }
    ]
  }
  let(:size_lookup_data) {
    [
      { dept: '185', class: '1957', nrf_size_code: '0', omni_size_code: '272980', refinement_size: '1', 'omniSizeDesc' => '272980', 'refinementSize' => '1' },
      { dept: '186', class: '1957', nrf_size_code: '33904', omni_size_code: '272981', refinement_size: '2', 'omniSizeDesc' => '272981', 'refinementSize' => '2' },
      { dept: '187', class: '1959', nrf_size_code: '33905', omni_size_code: '272982', refinement_size: '3', 'omniSizeDesc' => '272982', 'refinementSize' => '3' },
      { dept: '113', class: '1112', nrf_size_code: '33906', omni_size_code: '272982', refinement_size: '3', 'omniSizeDesc' => '272982', 'refinementSize' => '3' },
      { dept: '111', class: '1110', nrf_size_code: '33906', omni_size_code: '272982', refinement_size: '3', 'omniSizeDesc' => '272982', 'refinementSize' => '3' }
    ]
  }
  let(:color_lookup_data) {
    [
      { color_code: '001', super_color_code: '1', refinement_color: 'blue', 'omniChannelColorDescription' => '1', 'refinementColor' => 'blue' },
      { color_code: '002', super_color_code: '1', refinement_color: 'blue', 'omniChannelColorDescription' => '1', 'refinementColor' => 'blue' },
      { color_code: '003', super_color_code: '1', refinement_color: 'blue', 'omniChannelColorDescription' => '1', 'refinementColor' => 'blue' },
      { color_code: '004', super_color_code: '1', refinement_color: 'blue', 'omniChannelColorDescription' => '1', 'refinementColor' => 'blue' },
      { color_code: '015', super_color_code: '1', refinement_color: 'blue', 'omniChannelColorDescription' => '1', 'refinementColor' => 'blue' },
      { color_code: '020', super_color_code: '20', refinement_color: 'brown', 'omniChannelColorDescription' => '20', 'refinementColor' => 'brown' },
      { color_code: '021', super_color_code: '20', refinement_color: 'brown', 'omniChannelColorDescription' => '20', 'refinementColor' => 'brown' },
      { color_code: '022', super_color_code: '20', refinement_color: 'brown', 'omniChannelColorDescription' => '20', 'refinementColor' => 'brown' },
      { color_code: '023', super_color_code: '20', refinement_color: 'brown', 'omniChannelColorDescription' => '20', 'refinementColor' => 'brown' },
      { color_code: '024', super_color_code: '20', refinement_color: 'brown', 'omniChannelColorDescription' => '20', 'refinementColor' => 'brown' }
    ]
  }
  let(:brand_lookup_data) {
    [
      { vendor_number: '10003999', omni_brand_name: '1', 'OmniChannel Brand' => '1' },
      { vendor_number: '6200325', omni_brand_name: '10', 'OmniChannel Brand' => '10' }
    ]
  }

  before :each do
    allow_any_instance_of(Enrichment::Dictionary).to receive(:salsify_client) { nil }
    allow(dictionary).to receive(:google_sheet).and_return(google_sheet)
    allow(dictionary).to receive(:attribute_export).and_return(attributes)
    allow(dictionary).to receive(:attribute_value_export).and_return(attribute_values)
    allow(google_sheet).to receive(:category_data).and_return(category_lookup_data)
    allow(google_sheet).to receive(:dept_iph_data).and_return(iph_lookup_data)
    allow(google_sheet).to receive(:size_data).and_return(size_lookup_data)
    allow(google_sheet).to receive(:color_data).and_return(color_lookup_data)
    allow(google_sheet).to receive(:brand_data).and_return(brand_lookup_data)
  end

end
