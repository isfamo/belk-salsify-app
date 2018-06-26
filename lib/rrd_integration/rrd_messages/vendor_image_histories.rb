module RRDonnelley
  class VendorImageHistories

    attr_reader :vendor_images

    def initialize(vendor_images)
      @vendor_images = vendor_images
    end

    def self.from_xml(child)
      new(child.children.select do |child|
        child.name.downcase == 'vendorimage'
      end.map do |vendor_image|
        VendorImage.from_xml(vendor_image)
      end)
    end

    def to_xml
      xml = Builder::XmlMarkup.new
      xml.tag!('vendorImageHistories') do |vendorImageHistories|
        vendor_images.each do |vendor_image|
          vendorImageHistories << vendor_image.to_xml(image_id_attribute: 'id')
        end
      end
      xml.target!
    end

  end
end
