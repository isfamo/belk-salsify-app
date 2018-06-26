shared_examples 'dictionary_inputs' do

  let(:dictionary) { Enrichment::Dictionary.new }
  let(:google_sheet) { Enrichment::Dictionary::GoogleSheet.new }
  let(:attributes) { CSV.read('spec/lib/enrichment_integration/fixtures/attributes.csv', headers: true) }
  let(:attribute_values) { CSV.read('spec/lib/enrichment_integration/fixtures/attribute_values.csv', headers: true) }
  let(:category_lookup_data) {
    [
      { category_mapping: 'For the Home///1111', category: 'For the Home', attribute: 'Material', attribute_values: '100%Polyester|100%PolyesterBag', category_specific: 'true', mandatory: 'Yes' },
      { category_mapping: 'For the Home///1111///Bath', category: 'For the Home > Bath', attribute: 'Pattern', attribute_values: 'Bandana | Ditsy', category_specific: 'true', mandatory: 'Yes' },
      { category_mapping: 'For the Home///1111///Bath////Shiza', category: 'For the Home > Bath > Shiza', attribute: 'Pattern', attribute_values: 'Bandana', category_specific: 'true', mandatory: 'No' },
      { category_mapping: 'For the Home///1111///Bath////Towels', category: 'For the Home > Bath > Towels', attribute: 'Type', attribute_values: 'Hand towel | Bath towel ', category_specific: 'true', mandatory: 'No' },
      { category_mapping: 'Mens///2222/Pants', category: 'Mens > Pants', attribute: 'Material', attribute_values: '100%Cotton|100%Polyester', category_specific: 'true', mandatory: 'Yes' }
    ]
  }
  let(:iph_lookup_data) {
    [
      { dept: '111', class: '1110', eis_hier_iph_name: 'Women > Coats > Puffer ', 'iphCategory' => ['Women > Coats > Puffer'] },
      { dept: '111', class: '1110', eis_hier_iph_name: 'Women > Coats > Vest', 'iphCategory' => ['Women > Coats > Vest'] },
      { dept: '113', class: '1112', eis_hier_iph_name: 'Women > Coats > Parka', 'iphCategory' => ['Women > Coats > Parka'] },
      { dept: '114', class: '1113', eis_hier_iph_name: 'For the Home > Bath', 'iphCategory' => ['For the Home > Bath'] }
    ]
  }
  let(:size_lookup_data) {
    [
      { dept: '185', nrf_size_code: '0', omni_size_desc: '272980', facet_size_1: 'S', facet_size_2: 'M', facet_size_3: 'XXL', facet_sub_size_1: 'S', facet_sub_size_2: 'M', facet_sub_size_3: 'XXL', 'omniSizeDesc' => '272980', 'refinementSize' => ['S','M','XXL'], 'Refinement SubSize' => ['S','M','XXL'] },
      { dept: '186', nrf_size_code: '33904', omni_size_desc: '272981', facet_size_1: 'M', facet_size_2: 'XL', facet_size_3: 'XXL', facet_sub_size_1: 'S', facet_sub_size_2: 'M', facet_sub_size_3: 'XXL', 'omniSizeDesc' => '272981', 'refinementSize' => ['M','XL','XXL'], 'Refinement SubSize' => ['S','M','XXL'] },
      { dept: '187', nrf_size_code: '33905', omni_size_desc: '272982', facet_size_1: 'L', facet_size_2: 'XL', facet_size_3: 'XXL', facet_sub_size_1: 'S', facet_sub_size_2: 'M', facet_sub_size_3: 'XXL', 'omniSizeDesc' => '272982', 'refinementSize' => ['L','XL','XXL'], 'Refinement SubSize' => ['S','M','XXL'] },
      { dept: '113', nrf_size_code: '33906', omni_size_desc: '272982', facet_size_1: 'L', facet_size_2: 'XL', facet_size_3: 'XXL', facet_sub_size_1: 'S', facet_sub_size_2: 'M', facet_sub_size_3: 'XXL', 'omniSizeDesc' => '272982', 'refinementSize' => ['L','XL','XXL'], 'Refinement SubSize' => ['S','M','XXL'] },
      { dept: '111', nrf_size_code: '33906', omni_size_desc: '272982', facet_size_1: 'L', facet_size_2: 'XL', facet_size_3: 'XXL', facet_sub_size_1: 'S', facet_sub_size_2: 'M', facet_sub_size_3: 'XXL', 'omniSizeDesc' => '272982', 'refinementSize' => ['L','XL','XXL'], 'Refinement SubSize' => ['S','M','XXL'] }
    ]
  }
  let(:color_lookup_data) {
    [
      { nrf_color_code: '001', omni_color: '1', refinement_color: 'blue', 'omniChannelColorDescription' => ['1'], 'refinementColor' => ['blue'] },
      { nrf_color_code: '002', omni_color: '1', refinement_color: 'blue', 'omniChannelColorDescription' => ['1'], 'refinementColor' => ['blue'] },
      { nrf_color_code: '003', omni_color: '1', refinement_color: 'blue', 'omniChannelColorDescription' => ['1'], 'refinementColor' => ['blue'] },
      { nrf_color_code: '004', omni_color: '1', refinement_color: 'blue', 'omniChannelColorDescription' => ['1'], 'refinementColor' => ['blue'] },
      { nrf_color_code: '015', omni_color: '1', refinement_color: 'blue', 'omniChannelColorDescription' => ['1'], 'refinementColor' => ['blue'] },
      { nrf_color_code: '020', omni_color: '20', refinement_color: 'brown', 'omniChannelColorDescription' => ['20'], 'refinementColor' => ['brown'] },
      { nrf_color_code: '021', omni_color: '20', refinement_color: 'brown', 'omniChannelColorDescription' => ['20'], 'refinementColor' => ['brown'] },
      { nrf_color_code: '022', omni_color: '20', refinement_color: 'brown', 'omniChannelColorDescription' => ['20'], 'refinementColor' => ['brown'] },
      { nrf_color_code: '023', omni_color: '20', refinement_color: 'brown', 'omniChannelColorDescription' => ['20'], 'refinementColor' => ['brown'] },
      { nrf_color_code: '024', omni_color: '20', refinement_color: 'brown', 'omniChannelColorDescription' => ['20'], 'refinementColor' => ['brown'] }
    ]
  }
  let(:brand_lookup_data) {
    [
      { vendor_number: '10003999', omni_brand_name: '1', 'OmniChannel Brand' => ['1'] },
      { vendor_number: '6200325', omni_brand_name: '10', 'OmniChannel Brand' => ['10'] }
    ]
  }
  let(:non_selectable_categories_data ) {
    [
      { category: 'For the Home' }, { category: 'For the Home > Bath' }
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
    allow(google_sheet).to receive(:non_selectable_categories_data).and_return(non_selectable_categories_data)
  end

end
