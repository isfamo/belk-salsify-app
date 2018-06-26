class UpdateParentIds
  include Muffin::SftpClient

  REMOTE_LOCATION = 'scratch/parent_ids.csv'.freeze
  FILE_LOCATION = 'lib/cfh_integration/cache/parent_ids.csv'.freeze

  def self.run
    new.run
  end

  def run
    download_file_from_ftp
    parent_mapping
    update_skus
  end

  def download_file_from_ftp
    sftp.download!(REMOTE_LOCATION, FILE_LOCATION)
  end

  def update_skus
    parent_mapping.each_with_index do |(sku, parent), index|
      puts "UPDATE PARENTS - #{index}..." if index % 1000 == 0
      _sku = Sku.find_by(product_id: sku)
      next unless _sku
      next if _sku.parent_id == parent
      puts "updating #{sku} with parent #{parent} from parent #{_sku.parent_id}..."
      _parent = ParentProduct.find_by(product_id: parent)
      if _parent
        _sku.update(parent_id: parent, parent_product_id: _parent.id)
      else
        _parent = ParentProduct.create!(product_id: parent)
        _sku.update(parent_id: parent, parent_product_id: _parent.id)
      end
    end
  end

  def parent_mapping
    @parent_mapping ||= CSV.read(FILE_LOCATION, headers: true).map do |row|
      next unless row['salsify:parent_id']
      [ row['product_id'], row['salsify:parent_id'] ]
    end.compact
  end

end
