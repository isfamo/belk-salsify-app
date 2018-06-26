require './lib/image_management/helpers.rb'
require './lib/image_management/constants.rb'
require './lib/image_management/image_metadata.rb'
require './lib/image_management/image_rejection.rb'
require './lib/image_management/image_task.rb'

ENV['CARS_ENVIRONMENT'] = 'test'
ENV['SALSIFY_SUPERUSER_TOKEN'] = 'mytoken'

describe ImageManagement do
  let(:fixtures_dir) { './spec/lib/image_management/fixtures' }
  let(:styles) { load_fixture_json('styles.json') }
  let(:skus) { load_fixture_json('skus.json') }
  let(:assets) { load_fixture_json('assets.json') }
  let(:style_id) { '32033401290140' }
  let(:sku_id) { '0438574759893' }
  let(:asset_id) { '0cdfa40aa71c477a82f9b5fdc1f95106efad8f4f' }
  let(:query_lists_response) { [{ 'id' => '100001' }, { 'id' => '100002' }] }

  before :each do
    allow_any_instance_of(ImageManagement::Helpers).to receive(:query_lists).and_return(query_lists_response)
    allow_any_instance_of(ImageManagement::Helpers).to receive(:update_list).and_return(nil)
  end

  describe ImageManagement::ImageMetadata do
    before :each do
      allow_any_instance_of(ImageManagement::ImageMetadata).to receive(:style_by_id).and_return(styles.map { |s| [s['salsify:id'], s] }.to_h)
      allow_any_instance_of(ImageManagement::ImageMetadata).to receive(:asset_by_id).and_return(assets.map { |a| [a['salsify:id'], a] }.to_h)
      allow_any_instance_of(ImageManagement::ImageMetadata).to receive(:execute_asset_updates).and_return(nil)
      allow_any_instance_of(ImageManagement::ImageMetadata).to receive(:execute_product_updates).and_return(nil)
    end

    context self do
      it 'should generate metadata on first attach' do
        assets.first['image_metadata'] = "{}"
        allow_any_instance_of(ImageManagement::ImageMetadata).to receive(:asset_by_id).and_return(assets.map { |a| [a['salsify:id'], a] }.to_h)

        im = ImageManagement::ImageMetadata.new(skus)
        im.process_metadata
        asset_updates_by_id = im.asset_updates_by_id
        product_updates_by_id = im.product_updates_by_id

        expected_image_metadata_json = "{\"32033401290140_158\":{\"filename\":\"3203340_1290140_C_158.jpg\",\"approved\":false}}"
        expect(asset_updates_by_id.length == 1)
        expect(asset_updates_by_id[asset_id]['image_metadata'] == expected_image_metadata_json)
      end

      it 'should skip metadata if already there for same shot' do
        im = ImageManagement::ImageMetadata.new(skus)
        im.process_metadata
        asset_updates_by_id = im.asset_updates_by_id
        product_updates_by_id = im.product_updates_by_id

        expect(asset_updates_by_id.empty?)
      end

      it 'should generate metadata on subsequent attach with other shot' do
        skus.first.delete('Vendor Images - C - imagePath')
        skus.first['Vendor Images - B - imagePath'] = asset_id

        im = ImageManagement::ImageMetadata.new(skus)
        im.process_metadata
        asset_updates_by_id = im.asset_updates_by_id
        product_updates_by_id = im.product_updates_by_id

        expected_image_metadata_json = "{\"32033401290140_158\":{\"filename\":\"3203340_1290140_B_158.jpg\",\"approved\":false}}"
        expect(asset_updates_by_id.length == 1)
        expect(asset_updates_by_id[asset_id]['image_metadata'] == expected_image_metadata_json)
      end
    end

  end

  describe ImageManagement::ImageTask do
    before :each do
      allow_any_instance_of(ImageManagement::ImageTask).to receive(:execute_product_updates).and_return(nil)
    end

    context self do
      it 'should generate task id if does not exist' do
        ImageManagement::ImageTask.handle_task_complete(styles)
        task_id = RrdTaskId.find_by(product_id: style_id)
        expect(task_id)
      end

      it 'should not generate task id if it exists' do
        RrdTaskId.create(product_id: style_id)
        expect(RrdTaskId.count == 1)
        ImageManagement::ImageTask.handle_task_complete(styles)
        expect(RrdTaskId.count == 1)
      end
    end

  end

  def load_fixture_json(filename)
    Oj.load(File.read(File.join(fixtures_dir, filename)))
  end

end
