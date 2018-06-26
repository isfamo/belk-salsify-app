module RRDonnelley
  class CarsMessage

    attr_reader :type, :to, :from, :images_received, :images_processed, :children

    def initialize(attributes, children)
      @type = attributes['type']
      @to = attributes['to']
      @from = attributes['from']
      @images_received = attributes['imagesReceived']
      @images_processed = attributes['imagesProcessed']
      @children = [children].flatten
    end

    def self.from_xml(xml_text)
      xml = Nokogiri::XML(xml_text)
      msg = !xml.css('carsMessage').empty? ? xml.css('carsMessage').first : xml.css('carsmessage').first
      new(
        msg.attributes.map { |key, val| [key, val.value] }.to_h,
        parse_children(msg.children.reject { |child| child.is_a?(Nokogiri::XML::Text) && child.text.strip.empty? })
      )
    end

    def self.parse_children(children)
      children.map do |child|
        if child.name.downcase == 'vendorimage'
          VendorImage.from_xml(child)
        elsif child.name.downcase == 'image'
          ImageResult.from_xml(child)
        elsif child.name.downcase == 'vendorimagehistories'
          VendorImageHistories.from_xml(child)
        elsif child.name.downcase == 'productphotorequests'
          ProductPhotoRequests.from_xml(child)
        elsif child.name.downcase == 'histories'
          SampleHistories.from_xml(child)
        end
      end
    end

    def to_xml
      xml = Builder::XmlMarkup.new
      xml.tag!('carsMessage', {
        'type' => type,
        'to' => to,
        'from' => from,
        'imagesReceived' => images_received,
        'imagesProcessed' => images_processed
      }.reject { |_, val| val.nil? || val == '' }) do |carsMessage|
        children.each do |child|
          carsMessage << child.to_xml
        end
      end
    end

    def write_excel_copy(filepath)
      xls = WriteExcel.new(filepath)
      sheet = xls.add_worksheet
      row = 0
      if ['vendorimagesupload', 'vendorimagesupdate'].include?(type.downcase)
        write_excel_row(sheet, row, ['Image ID', 'Name', 'Uploaded By User', 'Status'])
        row += 1
        children.each do |vendor_image|
          write_excel_row(sheet, row, [
            vendor_image.image_id,
            vendor_image.name,
            vendor_image.uploaded_by_user,
            vendor_image.status
          ])
          row += 1
        end
      elsif ['photorequests'].include?(type.downcase)
        write_excel_row(sheet, row, [
          'CAR_ID',
          'On-Figure or Still Life',
          'Product_Type',
          'Product_Name',
          'Vendor_ID',
          'Vendor_Name',
          'Style_ID',
          'Brand',
          'Department_Code',
          'Department_Name',
          'Class_ID',
          'Class_Name',
          'Photo_Type',
          'Prefix',
          'Sample_ID',
          'Sample_Type',
          'Color_Code',
          'Color_Name',
          'Silhouette_Required',
          'Silhouette_Instructions',
          'style_colorcode'
        ])
        row += 1
        children.each do |photo_requests|
          photo_requests.product_photo_requests.each do |photo_request|
            photo_request.photos.each do |photo|
              photo.samples.each do |sample|
                write_excel_row(sheet, row, [
                  photo_request.car['id'],
                  photo.file['OForSLvalue'],
                  photo_request.product.type,
                  photo_request.product.name,
                  photo_request.product.vendor['id'],
                  photo_request.product.vendor['name'],
                  photo_request.product.style['id'],
                  photo_request.product.brand['name'],
                  photo_request.product.department['id'],
                  photo_request.product.department['name'],
                  photo_request.product._class['id'],
                  photo_request.product._class['name'],
                  photo.type,
                  photo.file['name']['prefix'],
                  sample.id,
                  sample.type,
                  sample.color['code'],
                  sample.color['name'],
                  sample.silhouette_required,
                  '', # TODO: silhouette_instructions?
                  "#{photo.file['name']['prefix'].split('_')[1]}_#{sample.color['code']}"
                ])
                row += 1
              end
            end
          end
        end
      end
      xls.close
      filepath
    end

    def write_excel_row(sheet, row_index, row_array)
      col_index = 0
      row_array.each do |cell|
        sheet.write(row_index, col_index, cell)
        col_index += 1
      end
    end
  end
end
